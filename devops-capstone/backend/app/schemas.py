"""Request and response shapes.

Validation lives here rather than in the routers so that a bad payload is
rejected before it reaches a session, and so the OpenAPI document at /docs is
accurate without being written twice.
"""
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models import AppointmentStatus


class DoctorCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    specialty: str = Field(min_length=2, max_length=80)
    room: str = Field(default="TBD", max_length=20)


class DoctorOut(DoctorCreate):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


class PatientCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    phone: str = Field(min_length=5, max_length=32)
    email: EmailStr | None = None


class PatientOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    phone: str
    email: str | None
    created_at: datetime


class AppointmentCreate(BaseModel):
    patient_id: int
    doctor_id: int
    scheduled_at: datetime
    duration_minutes: int = Field(default=30, ge=5, le=240)
    reason: str | None = Field(default=None, max_length=500)

    @field_validator("scheduled_at")
    @classmethod
    def _must_be_aware(cls, v: datetime) -> datetime:
        # A naive datetime is ambiguous the moment two timezones are involved,
        # and a clinic that books across a DST boundary will find out the hard
        # way. Reject it at the edge instead of guessing UTC.
        if v.tzinfo is None:
            raise ValueError("scheduled_at must include a timezone offset")
        return v


class AppointmentUpdate(BaseModel):
    scheduled_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, ge=5, le=240)
    status: AppointmentStatus | None = None
    reason: str | None = Field(default=None, max_length=500)

    @field_validator("scheduled_at")
    @classmethod
    def _must_be_aware(cls, v: datetime | None) -> datetime | None:
        if v is not None and v.tzinfo is None:
            raise ValueError("scheduled_at must include a timezone offset")
        return v


class AppointmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    patient_id: int
    doctor_id: int
    scheduled_at: datetime
    duration_minutes: int
    status: AppointmentStatus
    reason: str | None
    created_at: datetime
    patient_name: str | None = None
    doctor_name: str | None = None


class AppointmentStats(BaseModel):
    total: int
    scheduled: int
    completed: int
    cancelled: int
    no_show: int
    upcoming_7_days: int
    doctors: int
    patients: int
    completion_rate: float
