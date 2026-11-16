package com.wadadak.run.internal.recording;

import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

interface WithdrawnRunMemberRepository extends JpaRepository<WithdrawnRunMember, UUID> {
}
