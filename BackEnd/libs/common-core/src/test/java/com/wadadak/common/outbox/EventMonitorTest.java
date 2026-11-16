package com.wadadak.common.outbox;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.modulith.events.core.EventPublicationRepository;
import org.springframework.modulith.events.core.PublicationTargetIdentifier;
import org.springframework.modulith.events.core.TargetEventPublication;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(OutputCaptureExtension.class)
class EventMonitorTest {

    private final EventPublicationRepository repository = mock(EventPublicationRepository.class);
    private final EventMonitor monitor = new EventMonitor(repository,
            Clock.fixed(Instant.parse("2026-10-08T01:00:00Z"), ZoneOffset.UTC));

    @Test
    void summarizesStalePublicationsInOneLine(CapturedOutput output) {
        List<TargetEventPublication> stale = List.of(stale("listener-b", "2026-10-08T00:30:00Z"),
                stale("listener-a", "2026-10-08T00:10:00Z"),
                stale("listener-a", "2026-10-08T00:20:00Z"));
        when(repository.findIncompletePublicationsPublishedBefore(Instant.parse("2026-10-08T00:50:00Z"))).thenReturn(stale);

        monitor.warnStale();

        assertThat(output).contains("2026-10-08T00:10:00Z", "[listener-a, listener-b]");
    }

    @Test
    void staysQuietWithoutStalePublications(CapturedOutput output) {
        when(repository.findIncompletePublicationsPublishedBefore(any())).thenReturn(List.of());

        monitor.warnStale();

        assertThat(output).doesNotContain("EventMonitor");
    }

    private static TargetEventPublication stale(String listener, String publishedAt) {
        TargetEventPublication publication = mock(TargetEventPublication.class);
        when(publication.getTargetIdentifier()).thenReturn(PublicationTargetIdentifier.of(listener));
        when(publication.getPublicationDate()).thenReturn(Instant.parse(publishedAt));
        return publication;
    }
}
