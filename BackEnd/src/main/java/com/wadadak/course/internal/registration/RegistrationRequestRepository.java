package com.wadadak.course.internal.registration;

import org.springframework.data.jpa.repository.JpaRepository;

interface RegistrationRequestRepository extends JpaRepository<RegistrationRequest, RegistrationRequestKey> {
}
