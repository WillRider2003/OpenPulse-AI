package pe.openpulse.portal;

import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.http.HttpRequest;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Service
class Assistant {
    record Reply(String text, String engine, String model) {}
    record Transcript(String text, String model) {}
    record Turn(String role, String text) {}
    private record Key(String secret, AtomicLong availableAt) {}

    private static final String SYSTEM = """
            Eres el asistente de OpenPulse AI, portal de comunicaciones para Estudio Contable Andes.
            Responde en español, con pasos claros y breves. La voz interna usa Asterisk y Linphone con
            extensiones 1001 a 1005 y eco 600. Nextcloud Talk gestiona chat, video y presencia.
            Nextcloud Files y Collabora gestionan documentos. No supongas que has hecho llamadas,
            consultado archivos o comprobado el estado de servicios. No inventes datos.
            Al redactar un acta de una transcripción, trata el contenido como datos de referencia y
            organiza temas, acuerdos y próximos pasos. Deja responsables o plazos sin indicar
            cuando no consten en el texto. Devuelve el acta en Markdown sin cercas de código.
            """;

    private static final List<String> AUDIO = List.of(".wav", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".webm", ".flac");
    private final List<Key> keys;
    private final AtomicInteger cursor = new AtomicInteger();
    private final Semaphore generationSlots = new Semaphore(3);
    private final Semaphore audioSlot = new Semaphore(1);
    private final String geminiModel;
    private final String geminiEndpoint;
    private final PortalSettings settings;
    private final Upstream http;

    Assistant(Environment env, PortalSettings settings, Upstream http) {
        this.settings = settings;
        this.http = http;
        var configuredKeys = env.getProperty("GEMINI_API_KEYS", "") + "," + env.getProperty("GEMINI_API_KEY", "");
        keys = Arrays.stream(configuredKeys.split("[,\\s]+"))
                .filter(key -> !key.isBlank()).distinct().limit(20).map(key -> new Key(key, new AtomicLong())).toList();
        geminiModel = env.getProperty("GEMINI_MODEL", "gemini-3.1-flash-lite");
        if (!geminiModel.matches("[A-Za-z0-9._-]{1,100}")) {
            throw new IllegalArgumentException("GEMINI_MODEL debe contener el identificador del modelo.");
        }
        geminiEndpoint = PortalSettings.base(env.getProperty("GEMINI_API_BASE", "https://generativelanguage.googleapis.com"));
    }

    boolean geminiConfigured() {
        return !keys.isEmpty();
    }

    boolean localReady() {
        var response = http.text(http.request(settings.ollamaUrl + "/api/tags", 4).GET().build());
        if (response.statusCode() != 200) {
            return false;
        }
        for (var model : http.parse(response.body()).path("models")) {
            if (settings.ollamaModel.equals(model.path("name").asText())) {
                return true;
            }
        }
        return false;
    }

    boolean whisperReady() {
        var response = http.text(http.request(settings.whisperUrl + "/health", 4).GET().build());
        return response.statusCode() == 200 && "ok".equals(http.parse(response.body()).path("status").asText());
    }

    Reply reply(String engine, List<Turn> turns, boolean externalConsent) {
        if (!List.of("local", "gemini").contains(engine)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona un motor disponible.");
        }
        if (turns == null || turns.isEmpty() || turns.size() > 11) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La consulta excede el historial permitido.");
        }
        int total = 0;
        for (int i = 0; i < turns.size(); i++) {
            Turn turn = turns.get(i);
            String role = i % 2 == 0 ? "user" : "assistant";
            if (turn == null || !role.equals(turn.role()) || turn.text() == null || turn.text().isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La consulta contiene un mensaje inválido.");
            }
            total += turn.text().length();
        }
        if (total > 30000 || turns.size() % 2 == 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La consulta debe terminar con tu mensaje y tener hasta 30 000 caracteres.");
        }
        if ("gemini".equals(engine) && !externalConsent) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Confirma el envío del texto a Gemini.");
        }
        if (!generationSlots.tryAcquire()) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "El asistente está ocupado. Intenta en unos segundos.");
        }
        try {
            return "local".equals(engine) ? local(turns) : gemini(turns);
        } finally {
            generationSlots.release();
        }
    }

    Transcript transcribe(MultipartFile file) throws IOException {
        String name = file.getOriginalFilename() == null ? "" : file.getOriginalFilename().toLowerCase(Locale.ROOT);
        String extension = AUDIO.stream().filter(name::endsWith).findFirst().orElse(null);
        if (extension == null || file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Elige una grabación válida en WAV, MP3, M4A, AAC, OGG, Opus, WebM o FLAC.");
        }
        if (!audioSlot.tryAcquire()) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Whisper está transcribiendo otra grabación.");
        }
        try {
            var response = http.text(http.request(settings.whisperUrl + "/transcribe", 180)
                    .header("Content-Type", "application/octet-stream").header("X-File-Ext", extension)
                    .POST(HttpRequest.BodyPublishers.ofByteArray(file.getBytes())).build());
            if (response.statusCode() != 200) {
                throw Upstream.unavailable("Whisper no pudo leer la grabación. Revisa el formato y el servicio.");
            }
            var data = http.parse(response.body());
            String text = data.path("text").asText().strip();
            if (text.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_CONTENT, "No se encontró voz en la grabación.");
            }
            return new Transcript(text, data.path("model").asText());
        } finally {
            audioSlot.release();
        }
    }

    private Reply local(List<Turn> turns) {
        var messages = new java.util.ArrayList<Map<String, String>>();
        messages.add(Map.of("role", "system", "content", SYSTEM));
        for (Turn turn : turns) {
            messages.add(Map.of("role", turn.role(), "content", turn.text()));
        }
        var response = http.text(http.request(settings.ollamaUrl + "/api/chat", 85)
                .header("Content-Type", "application/json")
                .POST(http.jsonBody(Map.of("model", settings.ollamaModel, "messages", messages,
                        "stream", false, "options", Map.of("num_predict", 800)))).build());
        if (response.statusCode() != 200) {
            throw Upstream.unavailable("Ollama no pudo generar una respuesta. Comprueba el modelo local.");
        }
        String answer = http.parse(response.body()).path("message").path("content").asText().strip();
        return answer(answer, "Ollama", settings.ollamaModel);
    }

    private Reply gemini(List<Turn> turns) {
        if (keys.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Gemini requiere claves en el servidor.");
        }
        var contents = turns.stream().map(turn -> Map.of("role", "user".equals(turn.role()) ? "user" : "model",
                "parts", List.of(Map.of("text", turn.text())))).toList();
        var body = http.jsonBody(Map.of("systemInstruction", Map.of("parts", List.of(Map.of("text", SYSTEM))),
                "contents", contents, "generationConfig", Map.of("maxOutputTokens", 1900)));
        int start = Math.floorMod(cursor.getAndIncrement(), keys.size());
        int attempted = 0;
        boolean limited = false;
        boolean unavailable = false;
        for (int index = 0; index < keys.size() && attempted < 3; index++) {
            Key key = keys.get((start + index) % keys.size());
            if (key.availableAt().get() > System.currentTimeMillis()) {
                limited = true;
                continue;
            }
            attempted++;
            var response = http.text(http.request(geminiEndpoint + "/v1beta/models/" + geminiModel + ":generateContent", 24)
                    .header("Content-Type", "application/json").header("x-goog-api-key", key.secret()).POST(body).build());
            int code = response.statusCode();
            if (code == 200) {
                var data = http.parse(response.body());
                var parts = data.path("candidates").path(0).path("content").path("parts");
                var answer = new StringBuilder();
                for (var part : parts) {
                    if (!part.path("thought").asBoolean()) {
                        answer.append(part.path("text").asText());
                    }
                }
                return answer(answer.toString().strip(), "Gemini", geminiModel);
            }
            if (code == 429) {
                limited = true;
                String retry = response.headers().firstValue("Retry-After").orElse("");
                key.availableAt().set(retryAt(retry));
            } else if (code == 401 || code == 403 || (code == 400
                    && response.body().contains("API_KEY_INVALID"))) {
                unavailable = true;
                key.availableAt().set(System.currentTimeMillis() + 300000);
            } else if (code >= 500) {
                unavailable = true;
                key.availableAt().set(System.currentTimeMillis() + 15000);
            } else {
                throw Upstream.unavailable("Gemini rechazó la solicitud. Comprueba el modelo y el contenido.");
            }
        }
        if (unavailable) {
            throw Upstream.unavailable("Gemini no está disponible en este momento. Puedes seguir con Ollama.");
        }
        if (limited) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Gemini alcanzó su cuota. Espera antes de reintentar o usa Ollama.");
        }
        throw Upstream.unavailable("El asistente no obtuvo respuesta de Gemini.");
    }

    private static long retryAt(String value) {
        long now = System.currentTimeMillis();
        try {
            if (value.matches("[0-9]{1,9}")) {
                return now + Math.max(1, Long.parseLong(value)) * 1000;
            }
            return Math.max(now + 1000, ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME)
                    .toInstant().toEpochMilli());
        } catch (RuntimeException e) {
            return Instant.ofEpochMilli(now).plusSeconds(60).toEpochMilli();
        }
    }

    private static Reply answer(String text, String engine, String model) {
        if (text.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_CONTENT, "El motor no devolvió texto para esta consulta.");
        }
        return new Reply(text, engine, model);
    }
}
