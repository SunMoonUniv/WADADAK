package com.wadadak.run.internal.recording;

import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

interface DeletedRunRecordRepository extends JpaRepository<DeletedRunRecord, UUID> {
}
