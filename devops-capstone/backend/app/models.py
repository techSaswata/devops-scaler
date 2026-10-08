"""The domain: a clinic's doctors, patients and the appointments between them.

The interesting constraint is the unique index at the bottom. A clinic's real
failure mode is not a malformed payload, it is two patients booked into the
same doctor at the same moment -- and that is a race, so it cannot be prevented
by checking first and inserting afterwards. Two requests can both pass the
check before either inserts. The database is the only place that can settle it,
so the rule lives there as a partial unique index and the API turns the
resulting IntegrityError into a 409.
"""
import enum
from datetime import datetime, timezone

from sqlalchemy import (
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AppointmentStatus(str, enum.Enum):
    scheduled = "scheduled"
    completed = "completed"
    cancelled = "cancelled"
    no_show = "no_show"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Doctor(Base):
    __tablename__ = "doctors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    specialty: Mapped[str] = mapped_column(String(80), nullable=False)
    room: Mapped[str] = mapped_column(String(20), nullable=False, default="TBD")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    appointments: Mapped[list["Appointment"]] = relationship(back_populates="doctor")


class Patient(Base):
    __tablename__ = "patients"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False)
    email: Mapped[str | None] = mapped_column(String(160), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    appointments: Mapped[list["Appointment"]] = relationship(back_populates="patient")


class Appointment(Base):
    __tablename__ = "appointments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"), nullable=False, index=True
    )
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False, index=True
    )
    scheduled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    status: Mapped[AppointmentStatus] = mapped_column(
        Enum(AppointmentStatus, name="appointment_status"),
        nullable=False,
        default=AppointmentStatus.scheduled,
        index=True,
    )
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    patient: Mapped["Patient"] = relationship(back_populates="appointments")
    doctor: Mapped["Doctor"] = relationship(back_populates="appointments")

    __table_args__ = (
        # One doctor, one instant, one LIVE appointment. Cancelled and no-show
        # rows are excluded, because freeing a slot must not mean deleting the
        # history of who held it -- a cancelled appointment is a fact the clinic
        # needs to keep.
        Index(
            "uq_doctor_slot_live",
            "doctor_id",
            "scheduled_at",
            unique=True,
            postgresql_where=text("status IN ('scheduled', 'completed')"),
            sqlite_where=text("status IN ('scheduled', 'completed')"),
        ),
    )
