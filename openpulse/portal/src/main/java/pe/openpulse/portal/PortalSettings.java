package pe.openpulse.portal;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.util.List;

@Component
class PortalSettings {
    record Person(String name, String initials, String role, String extension, List<String> accounts) {}

    static final List<Person> TEAM = List.of(
            new Person("Willian Antaurco", "WA", "Integración y SSO", "1001", List.of("wantaurco", "willian.antaurco")),
            new Person("Rosell Pretel", "RP", "Voz y telefonía IP", "1002", List.of("rpretel", "rosell.pretel")),
            new Person("Abdón Vallejo", "AV", "Video, chat y presencia", "1003", List.of("avallejo", "abdon.vallejo")),
            new Person("Lucía Gil", "LG", "Documentos e IA", "1004", List.of("lgil", "lucia.gil")),
            new Person("Luis Paredes", "LP", "QoS y monitoreo", "1005", List.of("lparedes", "luis.paredes"))
    );

    final String cloudUrl;
    final String cloudPublic;
    final String ollamaUrl;
    final String ollamaModel;
    final String whisperUrl;
    final String sipDomain;
    final int sipPort;
    final String sipProbeHost;
    final String grafanaUrl;
    final String keycloakUrl;
    final String talkUrl;

    PortalSettings(Environment env) {
        cloudUrl = base(env.getProperty("NEXTCLOUD_INTERNAL_URL", "http://127.0.0.1:8080"));
        cloudPublic = base(env.getProperty("NEXTCLOUD_PUBLIC_URL", "http://localhost:8080"));
        ollamaUrl = base(env.getProperty("OLLAMA_URL", "http://127.0.0.1:11434"));
        ollamaModel = env.getProperty("OLLAMA_MODEL", "qwen2.5:0.5b");
        whisperUrl = base(env.getProperty("WHISPER_URL", "http://127.0.0.1:9000"));
        sipDomain = env.getProperty("SIP_DOMAIN", "localhost");
        sipPort = env.getProperty("SIP_TLS_PORT", Integer.class, 5061);
        sipProbeHost = env.getProperty("SIP_PROBE_HOST", sipDomain);
        grafanaUrl = base(env.getProperty("GRAFANA_PUBLIC_URL", "http://localhost:3000"));
        keycloakUrl = base(env.getProperty("KEYCLOAK_PUBLIC_URL", "http://localhost:8081"));
        String talk = env.getProperty("NEXTCLOUD_TALK_URL", "");
        talkUrl = talk.isBlank() ? cloudPublic + "/index.php/apps/spreed/" : base(talk);
        if (!sipDomain.matches("[A-Za-z0-9.-]{1,253}") || sipPort < 1 || sipPort > 65535) {
            throw new IllegalArgumentException("Configura un dominio SIP DNS o IPv4 y un puerto válido");
        }
    }

    static String base(String value) {
        URI uri = URI.create(value);
        if (!List.of("http", "https").contains(uri.getScheme()) || uri.getHost() == null
                || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null) {
            throw new IllegalArgumentException("Se requiere una URL base HTTP(S)");
        }
        return value.replaceFirst("/+$", "");
    }

    String sipAddress(String extension) {
        return extension + "@" + sipDomain + ":" + sipPort;
    }
}
