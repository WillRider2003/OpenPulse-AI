package pe.openpulse.portal;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

@Component
class Upstream {
    private final HttpClient client;
    final JsonMapper json;

    Upstream(HttpClient client, JsonMapper json) {
        this.client = client;
        this.json = json;
    }

    HttpRequest.Builder request(String url, int seconds) {
        return HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(seconds))
                .header("User-Agent", "OpenPulse Portal/1.0");
    }

    HttpRequest.BodyPublisher jsonBody(Object body) {
        return HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body));
    }

    HttpResponse<String> text(HttpRequest request) {
        return send(request, HttpResponse.BodyHandlers.ofString());
    }

    <T> HttpResponse<T> send(HttpRequest request, HttpResponse.BodyHandler<T> handler) {
        try {
            return client.send(request, handler);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw unavailable("Se interrumpió la conexión con el servicio.");
        } catch (IOException e) {
            throw unavailable("El servicio no respondió. Revisa su conexión y vuelve a intentar.");
        }
    }

    JsonNode parse(String content) {
        try {
            return json.readTree(content);
        } catch (RuntimeException e) {
            throw unavailable("El servicio devolvió una respuesta inválida.");
        }
    }

    static ResponseStatusException unavailable(String message) {
        return new ResponseStatusException(HttpStatus.BAD_GATEWAY, message);
    }
}
