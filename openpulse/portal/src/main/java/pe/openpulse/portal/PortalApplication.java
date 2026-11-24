package pe.openpulse.portal;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSessionEvent;
import jakarta.servlet.http.HttpSessionListener;
import org.springframework.boot.web.servlet.ServletListenerRegistrationBean;
import org.springframework.web.util.HttpSessionMutexListener;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Set;

@SpringBootApplication
public class PortalApplication {
    public static void main(String[] args) {
        SpringApplication.run(PortalApplication.class, args);
    }

    @Bean
    HttpClient integrationClient() {
        return HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(4))
                .followRedirects(HttpClient.Redirect.NEVER).build();
    }

    @Bean
    ServletListenerRegistrationBean<HttpSessionMutexListener> sessionMutex() {
        return new ServletListenerRegistrationBean<>(new HttpSessionMutexListener());
    }

    @Bean
    ServletListenerRegistrationBean<HttpSessionListener> revokeOnExpiry(Nextcloud cloud) {
        return new ServletListenerRegistrationBean<>(new HttpSessionListener() {
            @Override
            public void sessionDestroyed(HttpSessionEvent event) {
                var account = (Nextcloud.Account) event.getSession().getAttribute(PortalController.ACCOUNT);
                if (account != null) {
                    Thread.startVirtualThread(() -> cloud.revoke(account));
                }
            }
        });
    }

    @Bean
    OncePerRequestFilter portalHeaders() {
        return new OncePerRequestFilter() {
            @Override
            protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                            FilterChain chain) throws ServletException, IOException {
                response.setHeader("Content-Security-Policy",
                        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                        + "font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
                response.setHeader("X-Content-Type-Options", "nosniff");
                response.setHeader("Referrer-Policy", "no-referrer");
                if (request.getServletPath().startsWith("/api/")) {
                    response.setHeader("Cache-Control", "no-store");
                    if (!Set.of("GET", "HEAD", "OPTIONS").contains(request.getMethod())
                            && !"1".equals(request.getHeader("X-OpenPulse"))) {
                        response.sendError(403);
                        return;
                    }
                }
                chain.doFilter(request, response);
            }
        };
    }
}
