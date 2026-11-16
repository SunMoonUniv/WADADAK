package com.wadadak.course.internal.registration;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

interface RegistrationRequestRepository extends JpaRepository<RegistrationRequest, UUID> {

    Optional<RegistrationRequest> findByMemberIdAndIdempotencyKey(UUID memberId, UUID idempotencyKey);
}
