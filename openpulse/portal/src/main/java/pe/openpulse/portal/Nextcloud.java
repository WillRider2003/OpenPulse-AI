package pe.openpulse.portal;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.util.UriUtils;
import org.w3c.dom.Element;
import org.xml.sax.InputSource;
import tools.jackson.databind.JsonNode;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Comparator;
import java.util.List;

@Service
class Nextcloud {
    record Login(String url, String token, Instant expires) {}
    record Account(String login, String secret, String id, String name) {}
    record Room(String token, String name, int unread, String url) {}
    record ChatMessage(int id, String author, String text, long timestamp, boolean own) {}
    record FileEntry(String name, String path, boolean folder, long size, String modified, String openUrl, String officeId) {}

    private static final List<String> OFFICE_TYPES = List.of("odt", "ods", "odp", "docx", "xlsx", "pptx", "doc", "xls", "ppt");
    private static final String ROOMS = "/ocs/v2.php/apps/spreed/api/v4/room?format=json";
    private static final String FLOW = "/index.php/login/v2";
    private final PortalSettings settings;
    private final Upstream http;

    Nextcloud(PortalSettings settings, Upstream http) {
        this.settings = settings;
        this.http = http;
    }

    Login begin() {
        var response = http.text(http.request(settings.cloudUrl + FLOW, 8)
                .header("Accept", "application/json").POST(HttpRequest.BodyPublishers.noBody()).build());
        check(response.statusCode());
        var json = http.parse(response.body());
        String rawUrl = json.path("login").asText();
        String token = json.path("poll").path("token").asText();
        var match = java.util.regex.Pattern.compile("/(?:index\\.php/)?login/v2/flow/([A-Za-z0-9_-]{20,512})$")
                .matcher(URI.create(rawUrl).getPath());
        if (!match.find() || !token.matches("[A-Za-z0-9_-]{20,512}")) {
            throw Upstream.unavailable("Nextcloud devolvió un enlace de conexión inválido.");
        }
        return new Login(settings.cloudPublic + FLOW + "/flow/" + match.group(1), token, Instant.now().plusSeconds(1180));
    }

    Account poll(Login pending) {
        var response = http.text(http.request(settings.cloudUrl + FLOW + "/poll", 8)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("token=" + form(pending.token()))).build());
        if (response.statusCode() == 404) {
            return null;
        }
        check(response.statusCode());
        var json = http.parse(response.body());
        String login = json.path("loginName").asText();
        String password = json.path("appPassword").asText();
        if (login.isBlank() || login.contains(":") || password.isBlank()) {
            throw Upstream.unavailable("Nextcloud no devolvió una credencial de aplicación válida.");
        }
        try {
            JsonNode data = ocs(ocsRequest(new Account(login, password, "", ""), "/ocs/v2.php/cloud/user?format=json")
                    .GET().build());
            String id = data.path("id").asText();
            validatePart(id);
            String name = data.path("display-name").asText();
            return new Account(login, password, id, name.isBlank() ? id : name);
        } catch (ResponseStatusException e) {
            revoke(new Account(login, password, "", ""));
            throw e;
        }
    }

    void revoke(Account account) {
        try {
            http.send(auth(settings.cloudUrl + "/ocs/v2.php/core/apppassword", 4, account.login(), account.secret())
                    .header("OCS-APIRequest", "true").DELETE().build(), HttpResponse.BodyHandlers.discarding());
        } catch (ResponseStatusException ignored) {
            // The portal session is invalidated even if Nextcloud is temporarily unavailable.
        }
    }

    boolean ready() {
        var r = http.text(http.request(settings.cloudUrl + "/status.php", 4).GET().build());
        if (r.statusCode() != 200) {
            return false;
        }
        var data = http.parse(r.body());
        return data.path("installed").asBoolean() && !data.path("maintenance").asBoolean()
                && !data.path("needsDbUpgrade").asBoolean();
    }

    List<Room> rooms(Account account) {
        JsonNode data = ocs(ocsRequest(account, ROOMS).GET().build());
        if (!data.isArray()) {
            throw Upstream.unavailable("Talk devolvió un listado inválido.");
        }
        var rooms = new ArrayList<Room>();
        for (var item : data) {
            String token = item.path("token").asText();
            if (token.matches("[A-Za-z0-9_-]{1,128}")) {
                rooms.add(new Room(token, item.path("displayName").asText("Conversación"),
                        item.path("unreadMessages").asInt(), roomUrl(token)));
            }
        }
        return rooms;
    }

    Room directRoom(Account account, String extension) {
        var contact = PortalSettings.TEAM.stream().filter(person -> person.extension().equals(extension))
                .findFirst().orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No existe esa extensión."));
        if (contact.accounts().contains(account.id())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona a otro integrante del equipo.");
        }
        String recipient = contact.accounts().get(account.id().contains(".") ? 1 : 0);
        JsonNode data = ocs(ocsRequest(account, ROOMS).header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("roomType=1&invite=" + form(recipient))).build());
        String token = data.path("token").asText();
        if (!token.matches("[A-Za-z0-9_-]{1,128}")) {
            throw Upstream.unavailable("Talk no devolvió un enlace a la conversación.");
        }
        return new Room(token, data.path("displayName").asText(contact.name()), 0, roomUrl(token));
    }

    List<ChatMessage> messages(Account account, String token) {
        var response = http.text(ocsRequest(account, chatPath(token)
                + "&lookIntoFuture=0&limit=40&noStatusUpdate=1").GET().build());
        if (response.statusCode() == 304) {
            return List.of();
        }
        var result = new ArrayList<ChatMessage>();
        for (var item : ocs(response)) {
            if ("comment".equals(item.path("messageType").asText()) || "comment".equals(item.path("type").asText())) {
                result.add(chatMessage(account, item));
            }
        }
        result.sort(Comparator.comparingInt(ChatMessage::id));
        return result;
    }

    ChatMessage sendMessage(Account account, String token, String message) {
        if (message == null || message.isBlank() || message.length() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Escribe un mensaje de hasta 1000 caracteres.");
        }
        JsonNode item = ocs(ocsRequest(account, chatPath(token)).header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("message=" + form(message.strip()))).build());
        return chatMessage(account, item);
    }

    void shareWithRoom(Account account, String token, String path) {
        validateRoomToken(token);
        dav(account, path);
        ocs(ocsRequest(account, "/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("shareType=10&shareWith=" + form(token) + "&path=" + form("/" + path)))
                .build());
    }

    private static ChatMessage chatMessage(Account account, JsonNode item) {
        return new ChatMessage(item.path("id").asInt(), item.path("actorDisplayName").asText("Usuario de Talk"),
                item.path("message").asText(), item.path("timestamp").asLong(),
                account.id().equals(item.path("actorId").asText()));
    }

    private static String chatPath(String token) {
        validateRoomToken(token);
        return "/ocs/v2.php/apps/spreed/api/v1/chat/" + token + "?format=json";
    }

    private static void validateRoomToken(String token) {
        if (token == null || !token.matches("[A-Za-z0-9_-]{1,128}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona una conversación válida.");
        }
    }

    java.util.Map<String, String> presence(Account account) {
        JsonNode data = ocs(ocsRequest(account, "/ocs/v2.php/apps/user_status/api/v1/statuses?limit=100&format=json")
                .GET().build());
        var statuses = new java.util.HashMap<String, String>();
        for (var item : data) {
            String status = item.path("status").asText();
            if (List.of("online", "away", "dnd", "offline").contains(status)) {
                statuses.put(item.path("userId").asText(), status);
            }
        }
        var teamStatuses = new java.util.HashMap<String, String>();
        for (var person : PortalSettings.TEAM) {
            var status = person.accounts().stream()
                    .filter(statuses::containsKey).map(statuses::get).findFirst();
            status.ifPresent(value -> teamStatuses.put(person.extension(), value));
        }
        return teamStatuses;
    }

    private String roomUrl(String token) {
        return settings.cloudPublic + "/index.php/call/" + token;
    }

    private HttpRequest.Builder ocsRequest(Account account, String path) {
        return auth(settings.cloudUrl + path, 10, account.login(), account.secret()).header("OCS-APIRequest", "true");
    }

    private JsonNode ocs(HttpRequest request) {
        return ocs(http.text(request));
    }

    private JsonNode ocs(HttpResponse<String> response) {
        check(response.statusCode());
        var envelope = http.parse(response.body()).path("ocs");
        int status = envelope.path("meta").path("statuscode").asInt();
        if (status != 100) {
            check(status >= 200 && status < 300 ? 200 : status);
        }
        return envelope.path("data");
    }

    List<FileEntry> list(Account account, String path) {
        String url = dav(account, path);
        String directory = url.endsWith("/") ? url : url + "/";
        var response = http.text(auth(directory, 12, account.login(), account.secret())
                .header("Depth", "1").header("Content-Type", "application/xml; charset=UTF-8")
                .method("PROPFIND", HttpRequest.BodyPublishers.ofString("""
                        <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop>
                          <d:resourcetype/><d:getcontentlength/><d:getlastmodified/><oc:fileid/>
                        </d:prop></d:propfind>
                        """)).build());
        check(response.statusCode());
        return parseFiles(response.body(), URI.create(directory).getPath(), path);
    }

    String openOffice(Account account, String fileId) {
        if (!fileId.matches("[0-9]{1,18}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona un documento válido.");
        }
        var data = ocs(ocsRequest(account, "/ocs/v2.php/apps/richdocuments/api/v1/document?format=json")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("fileId=" + fileId)).build());
        var match = java.util.regex.Pattern.compile("/apps/richdocuments/direct/([A-Za-z0-9_-]{16,256})$")
                .matcher(URI.create(data.path("url").asText()).getPath());
        if (!match.find()) {
            throw Upstream.unavailable("Nextcloud Office no devolvió un enlace válido al editor.");
        }
        return settings.cloudPublic + "/index.php/apps/richdocuments/direct/" + match.group(1);
    }

    HttpResponse<InputStream> download(Account account, String path) {
        var response = http.send(auth(dav(account, path), 20, account.login(), account.secret())
                .GET().build(), HttpResponse.BodyHandlers.ofInputStream());
        if (response.statusCode() != 200) {
            try (var ignored = response.body()) {
                check(response.statusCode());
            } catch (IOException e) {
                throw Upstream.unavailable("No se pudo descargar el archivo.");
            }
            throw Upstream.unavailable("Nextcloud devolvió una descarga incompleta.");
        }
        return response;
    }

    void upload(Account account, String path, byte[] content) {
        check(http.send(auth(dav(account, path), 45, account.login(), account.secret())
                .header("If-None-Match", "*").header("Content-Type", "application/octet-stream")
                .PUT(HttpRequest.BodyPublishers.ofByteArray(content)).build(),
                HttpResponse.BodyHandlers.discarding()).statusCode());
    }

    static String append(String folder, String filename) {
        validatePart(filename);
        return folder.isEmpty() ? filename : folder + "/" + filename;
    }

    private List<FileEntry> parseFiles(String xml, String directory, String path) {
        try {
            var factory = DocumentBuilderFactory.newInstance();
            factory.setNamespaceAware(true);
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
            var responses = factory.newDocumentBuilder().parse(new InputSource(new StringReader(xml)))
                    .getElementsByTagNameNS("DAV:", "response");
            var result = new ArrayList<FileEntry>();
            for (int index = 0; index < responses.getLength(); index++) {
                var item = (Element) responses.item(index);
                String remote = URI.create(element(item, "DAV:", "href")).getPath();
                if (remote == null || !remote.startsWith(directory)) {
                    continue;
                }
                String name = remote.substring(directory.length()).replaceFirst("/$", "");
                if (name.isEmpty() || name.contains("/")) {
                    continue;
                }
                boolean folder = item.getElementsByTagNameNS("DAV:", "collection").getLength() > 0;
                String id = element(item, "http://owncloud.org/ns", "fileid");
                String size = element(item, "DAV:", "getcontentlength");
                boolean hasId = id.matches("[0-9]+");
                String extension = name.substring(name.lastIndexOf('.') + 1).toLowerCase(java.util.Locale.ROOT);
                String officeId = hasId && !folder && OFFICE_TYPES.contains(extension) ? id : "";
                result.add(new FileEntry(name, append(path, name), folder,
                        size.matches("[0-9]{1,18}") ? Long.parseLong(size) : 0,
                        isoDate(element(item, "DAV:", "getlastmodified")),
                        hasId ? settings.cloudPublic + "/index.php/f/" + id : "", officeId));
            }
            result.sort(Comparator.comparing(FileEntry::folder).reversed()
                    .thenComparing(FileEntry::name, String.CASE_INSENSITIVE_ORDER));
            return result;
        } catch (Exception e) {
            throw Upstream.unavailable("No se pudo interpretar el listado de Nextcloud.");
        }
    }

    private static String element(Element parent, String namespace, String tag) {
        var nodes = parent.getElementsByTagNameNS(namespace, tag);
        return nodes.getLength() == 0 ? "" : nodes.item(0).getTextContent();
    }

    private static String isoDate(String value) {
        try {
            return ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toString();
        } catch (DateTimeParseException e) {
            return "";
        }
    }

    private String dav(Account account, String path) {
        StringBuilder url = new StringBuilder(settings.cloudUrl).append("/remote.php/dav/files/")
                .append(UriUtils.encodePathSegment(account.id(), StandardCharsets.UTF_8)).append("/");
        if (path.length() > 1600) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La ruta del archivo es demasiado larga.");
        }
        if (!path.isEmpty()) {
            for (String part : path.split("/", -1)) {
                validatePart(part);
                if (url.charAt(url.length() - 1) != '/') {
                    url.append('/');
                }
                url.append(UriUtils.encodePathSegment(part, StandardCharsets.UTF_8));
            }
        }
        return url.toString();
    }

    private static void validatePart(String part) {
        if (part.isBlank() || part.equals(".") || part.equals("..") || part.length() > 255
                || part.indexOf('/') >= 0 || part.indexOf('\\') >= 0
                || part.codePoints().anyMatch(Character::isISOControl)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El nombre o la ruta del archivo no es válido.");
        }
    }

    private HttpRequest.Builder auth(String url, int timeout, String login, String secret) {
        String basic = Base64.getEncoder().encodeToString((login + ":" + secret).getBytes(StandardCharsets.UTF_8));
        return http.request(url, timeout).header("Authorization", "Basic " + basic);
    }

    private static String form(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static void check(int code) {
        if (code >= 200 && code < 300) {
            return;
        }
        switch (code) {
            case 401 -> throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Vuelve a conectar tu cuenta de Nextcloud.");
            case 403 -> throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Tu cuenta no tiene permiso para esta operación.");
            case 404 -> throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Nextcloud no encontró el recurso.");
            case 409, 412 -> throw new ResponseStatusException(HttpStatus.CONFLICT, "Nextcloud rechazó la operación por un conflicto o una condición pendiente.");
            case 400 -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Nextcloud rechazó los datos enviados.");
            case 429 -> throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Nextcloud pidió esperar antes de reintentar.");
            case 413, 507 -> throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "El archivo supera el límite o la cuota de Nextcloud.");
            default -> throw Upstream.unavailable("Nextcloud no pudo completar la operación.");
        }
    }
}
