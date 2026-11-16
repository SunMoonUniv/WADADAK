package com.wadadak.ranking.internal.course;

import java.time.Instant;
import java.util.UUID;

/** Public representative metadata only. Raw GPS and private sensor metrics are never included. */
record PublicGhostCandidate(UUID runRecordId, UUID memberId, int rank, int courseElapsedSeconds,
                            String nickname, String profileImageUrl, int paceSecondsPerKm, Instant completedAt) {}
