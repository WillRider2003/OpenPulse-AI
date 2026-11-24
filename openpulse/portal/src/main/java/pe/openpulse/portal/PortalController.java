package pe.openpulse.portal;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.web.util.WebUtils;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.function.BooleanSupplier;

@RestController
@RequestMapping("/api")
class PortalController {
    record Contact(String name, String initials, String role, String extension, String dial, String address, boolean self) {}
    record User(String name, String extension) {}
    record Config(User user, List<Contact> team, String cloud, String talk, String echo,
                  String sipHost, String cloudAdmin, String identity, String metrics, boolean gemini) {}
    record ChatInput(String text) {}
    record ShareInput(String token, String path) {}
    record Query(String engine, List<Assistant.Turn> turns, boolean externalConsent) {}
    record Acta(String filename, String text, String folder) {}

    private static final String LOGIN = "nextcloudLogin";
    static final String ACCOUNT = "nextcloudAccount";

    private final PortalSettings settings;
    private final Nextcloud cloud;
    private final Assistant assistant;

    PortalController(PortalSettings settings, Nextcloud cloud, Assistant assistant) {
        this.settings = settings;
        this.cloud = cloud;
        this.assistant = assistant;
    }

    @GetMapping("/config")
    Config config(HttpServletRequest request) {
        var account = optionalAccount(request);
        var ownContact = account == null ? null : PortalSettings.TEAM.stream()
                .filter(person -> person.accounts().contains(account.id())).findFirst().orElse(null);
        var team = PortalSettings.TEAM.stream().map(person -> new Contact(person.name(), person.initials(), person.role(),
                person.extension(), dial(person.extension()), "sips:" + settings.sipAddress(person.extension()),
                person.equals(ownContact))).toList();
        User user = account == null ? null : new User(account.name(), ownContact == null ? "" : ownContact.extension());
        return new Config(user, team, settings.cloudPublic + "/index.php/apps/files/", settings.talkUrl, dial("600"),
                settings.sipDomain + ":" + settings.sipPort, settings.cloudPublic + "/index.php/settings/users",
                settings.keycloakUrl + "/admin/", settings.grafanaUrl + "/d/openpulse-ai-sla", assistant.geminiConfigured());
    }

    @GetMapping("/status")
    Map<String, Boolean> statuses() {
        var nextcloud = probe(cloud::ready);
        var sip = probe(this::sipReady);
        var local = probe(assistant::localReady);
        var whisper = probe(assistant::whisperReady);
        return Map.of("nextcloud", nextcloud.join(), "sip", sip.join(),
                "local", local.join(), "whisper", whisper.join());
    }

    @PostMapping("/session/start")
    Map<String, String> begin(HttpServletRequest request) {
        HttpSession session = request.getSession();
        synchronized (WebUtils.getSessionMutex(session)) {
            if (session.getAttribute(ACCOUNT) != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Ya tienes una cuenta conectada.");
            }
            var login = (Nextcloud.Login) session.getAttribute(LOGIN);
            if (login == null || login.expires().isBefore(Instant.now())) {
                login = cloud.begin();
                session.setAttribute(LOGIN, login);
            }
            return Map.of("url", login.url(), "expires", login.expires().toString());
        }
    }

    @PostMapping("/session/poll")
    ResponseEntity<Void> poll(HttpServletRequest request) {
        HttpSession session = request.getSession(false);
        if (session == null) {
            return ResponseEntity.status(HttpStatus.GONE).build();
        }
        synchronized (WebUtils.getSessionMutex(session)) {
            if (session.getAttribute(ACCOUNT) != null) {
                return ResponseEntity.noContent().build();
            }
            var login = (Nextcloud.Login) session.getAttribute(LOGIN);
            if (login == null || login.expires().isBefore(Instant.now())) {
                session.removeAttribute(LOGIN);
                return ResponseEntity.status(HttpStatus.GONE).build();
            }
            Nextcloud.Account account;
            try {
                account = cloud.poll(login);
            } catch (ResponseStatusException e) {
                session.removeAttribute(LOGIN);
                throw e;
            }
            if (account == null) {
                return ResponseEntity.accepted().build();
            }
            request.changeSessionId();
            session.removeAttribute(LOGIN);
            session.setAttribute(ACCOUNT, account);
            return ResponseEntity.noContent().build();
        }
    }

    @DeleteMapping("/session")
    ResponseEntity<Void> logout(HttpServletRequest request) {
        var account = optionalAccount(request);
        HttpSession session = request.getSession(false);
        if (session != null) {
            session.removeAttribute(ACCOUNT);
            session.invalidate();
        }
        if (account != null) {
            cloud.revoke(account);
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/cloud")
    List<Nextcloud.FileEntry> files(HttpServletRequest request, @RequestParam(defaultValue = "") String path) {
        return cloud.list(requireAccount(request), path);
    }

    @GetMapping("/cloud/download")
    ResponseEntity<StreamingResponseBody> download(HttpServletRequest request, @RequestParam String path) {
        var account = requireAccount(request);
        if (path.isBlank() || path.endsWith("/")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona un archivo para descargar.");
        }
        var file = cloud.download(account, path);
        String name = path.substring(path.lastIndexOf('/') + 1);
        var headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
        headers.setContentDisposition(ContentDisposition.attachment().filename(name, StandardCharsets.UTF_8).build());
        file.headers().firstValueAsLong("Content-Length").ifPresent(headers::setContentLength);
        StreamingResponseBody body = output -> {
            try (var input = file.body()) {
                input.transferTo(output);
            }
        };
        return ResponseEntity.ok().headers(headers).body(body);
    }

    @PostMapping("/cloud/office/{fileId}")
    Map<String, String> office(HttpServletRequest request, @PathVariable String fileId) {
        return Map.of("url", cloud.openOffice(requireAccount(request), fileId));
    }

    @PostMapping(path = "/cloud/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    ResponseEntity<Void> upload(HttpServletRequest request, @RequestParam(defaultValue = "") String folder,
                                @RequestParam MultipartFile file) throws IOException {
        var account = requireAccount(request);
        String name = file.getOriginalFilename();
        if (name == null || name.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El archivo no tiene nombre.");
        }
        cloud.upload(account, Nextcloud.append(folder, name), file.getBytes());
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    @GetMapping("/talk/rooms")
    List<Nextcloud.Room> rooms(HttpServletRequest request) {
        return cloud.rooms(requireAccount(request));
    }

    @PostMapping("/talk/direct/{extension}")
    Nextcloud.Room direct(HttpServletRequest request, @PathVariable String extension) {
        return cloud.directRoom(requireAccount(request), extension);
    }

    @GetMapping("/talk/rooms/{token}/messages")
    List<Nextcloud.ChatMessage> messages(HttpServletRequest request, @PathVariable String token) {
        return cloud.messages(requireAccount(request), token);
    }

    @PostMapping("/talk/rooms/{token}/messages")
    Nextcloud.ChatMessage sendMessage(HttpServletRequest request, @PathVariable String token, @RequestBody ChatInput message) {
        return cloud.sendMessage(requireAccount(request), token, message.text());
    }

    @PostMapping("/talk/share")
    ResponseEntity<Void> share(HttpServletRequest request, @RequestBody ShareInput share) {
        var account = requireAccount(request);
        if (share.path() == null || !share.path().toLowerCase(java.util.Locale.ROOT).endsWith(".md")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona un acta guardada.");
        }
        cloud.shareWithRoom(account, share.token(), share.path());
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    @GetMapping("/presence")
    Map<String, String> presence(HttpServletRequest request) {
        return cloud.presence(requireAccount(request));
    }

    @PostMapping("/assistant/reply")
    Assistant.Reply reply(HttpServletRequest request, @RequestBody Query query) {
        requireAccount(request);
        return assistant.reply(query.engine() == null ? "" : query.engine(), query.turns(), query.externalConsent());
    }

    @PostMapping(path = "/assistant/transcribe", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    Assistant.Transcript transcribe(HttpServletRequest request, @RequestParam MultipartFile file) throws IOException {
        requireAccount(request);
        return assistant.transcribe(file);
    }

    @PostMapping("/assistant/save")
    ResponseEntity<Void> save(HttpServletRequest request, @RequestBody Acta acta) {
        var account = requireAccount(request);
        String name = acta.filename();
        if (name == null || !name.toLowerCase(java.util.Locale.ROOT).endsWith(".md")
                || acta.text() == null || acta.text().isBlank() || acta.text().length() > 30000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Indica un nombre .md y un acta de hasta 30 000 caracteres.");
        }
        String folder = acta.folder() == null ? "" : acta.folder();
        cloud.upload(account, Nextcloud.append(folder, name), acta.text().getBytes(StandardCharsets.UTF_8));
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<Map<String, String>> error(ResponseStatusException exception) {
        return ResponseEntity.status(exception.getStatusCode())
                .body(Map.of("message", exception.getReason() == null ? "No se pudo completar la operación." : exception.getReason()));
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<Map<String, String>> uploadSize() {
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(Map.of("message", "El límite por archivo es 24 MB."));
    }

    private String dial(String extension) {
        return "sip-linphone:" + settings.sipAddress(extension) + "?linphone-action=call&linphone-use-sips";
    }

    private boolean sipReady() {
        try (var connection = new Socket()) {
            connection.connect(new InetSocketAddress(settings.sipProbeHost, settings.sipPort), 1500);
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    private static CompletableFuture<Boolean> probe(BooleanSupplier supplier) {
        return CompletableFuture.supplyAsync(supplier::getAsBoolean).exceptionally(error -> false);
    }

    private static Nextcloud.Account optionalAccount(HttpServletRequest request) {
        HttpSession session = request.getSession(false);
        return session == null ? null : (Nextcloud.Account) session.getAttribute(ACCOUNT);
    }

    private static Nextcloud.Account requireAccount(HttpServletRequest request) {
        var account = optionalAccount(request);
        if (account == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Conecta tu cuenta de Nextcloud para continuar.");
        }
        return account;
    }
}
