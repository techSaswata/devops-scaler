"""Appointments: the five REST verbs plus the dashboard's stats query."""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import Appointment, AppointmentStatus, Doctor, Patient
from app.schemas import (
    AppointmentCreate,
    AppointmentOut,
    AppointmentStats,
    AppointmentUpdate,
)

router = APIRouter(prefix="/api/appointments", tags=["appointments"])

_LIVE = (AppointmentStatus.scheduled, AppointmentStatus.completed)


def _to_out(a: Appointment) -> AppointmentOut:
    out = AppointmentOut.model_validate(a)
    out.patient_name = a.patient.name if a.patient else None
    out.doctor_name = a.doctor.name if a.doctor else None
    return out


@router.get("", response_model=list[AppointmentOut])
def list_appointments(
    db: Session = Depends(get_db),
    status_filter: AppointmentStatus | None = Query(default=None, alias="status"),
    doctor_id: int | None = None,
    limit: int = Query(default=100, ge=1, le=500),
) -> list[AppointmentOut]:
    # joinedload, not lazy access in the loop: rendering 100 rows would
    # otherwise issue 201 queries (the classic N+1) and the dashboard would get
    # slower precisely as the clinic got busier.
    stmt = (
        select(Appointment)
        .options(joinedload(Appointment.patient), joinedload(Appointment.doctor))
        .order_by(Appointment.scheduled_at)
        .limit(limit)
    )
    if status_filter is not None:
        stmt = stmt.where(Appointment.status == status_filter)
    if doctor_id is not None:
        stmt = stmt.where(Appointment.doctor_id == doctor_id)
    return [_to_out(a) for a in db.scalars(stmt).unique()]


@router.get("/stats", response_model=AppointmentStats)
def appointment_stats(db: Session = Depends(get_db)) -> AppointmentStats:
    # One grouped query rather than five counts. /stats is called on every
    # dashboard poll, so it is the endpoint most worth not being lazy about.
    rows = dict(
        db.execute(
            select(Appointment.status, func.count()).group_by(Appointment.status)
        ).all()
    )
    by = {s: int(rows.get(s, 0)) for s in AppointmentStatus}
    total = sum(by.values())

    now = datetime.now(timezone.utc)
    upcoming = int(
        db.scalar(
            select(func.count())
            .select_from(Appointment)
            .where(
                Appointment.status == AppointmentStatus.scheduled,
                Appointment.scheduled_at >= now,
                Appointment.scheduled_at < now + timedelta(days=7),
            )
        )
        or 0
    )
    finished = by[AppointmentStatus.completed] + by[AppointmentStatus.no_show]
    return AppointmentStats(
        total=total,
        scheduled=by[AppointmentStatus.scheduled],
        completed=by[AppointmentStatus.completed],
        cancelled=by[AppointmentStatus.cancelled],
        no_show=by[AppointmentStatus.no_show],
        upcoming_7_days=upcoming,
        doctors=int(db.scalar(select(func.count()).select_from(Doctor)) or 0),
        patients=int(db.scalar(select(func.count()).select_from(Patient)) or 0),
        # Guarded: a brand-new clinic has no finished appointments, and
        # 0/0 would be a ZeroDivisionError on the dashboard's first load.
        completion_rate=round(
            (by[AppointmentStatus.completed] / finished * 100) if finished else 0.0, 1
        ),
    )


@router.get("/{appointment_id}", response_model=AppointmentOut)
def get_appointment(appointment_id: int, db: Session = Depends(get_db)) -> AppointmentOut:
    appointment = db.get(Appointment, appointment_id)
    if appointment is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "appointment not found")
    return _to_out(appointment)


@router.post("", response_model=AppointmentOut, status_code=status.HTTP_201_CREATED)
def create_appointment(
    payload: AppointmentCreate, db: Session = Depends(get_db)
) -> AppointmentOut:
    if db.get(Patient, payload.patient_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "patient not found")
    if db.get(Doctor, payload.doctor_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "doctor not found")

    appointment = Appointment(**payload.model_dump())
    db.add(appointment)
    try:
        db.commit()
    except IntegrityError:
        # The unique index did this, not a pre-flight check -- see models.py.
        # Two concurrent bookings can both pass a "is the slot free?" query, so
        # the database is the only thing that can decide, and 409 is the honest
        # answer rather than 400.
        db.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "that doctor already has an appointment at that time",
        ) from None
    db.refresh(appointment)
    return _to_out(appointment)


@router.put("/{appointment_id}", response_model=AppointmentOut)
def update_appointment(
    appointment_id: int, payload: AppointmentUpdate, db: Session = Depends(get_db)
) -> AppointmentOut:
    appointment = db.get(Appointment, appointment_id)
    if appointment is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "appointment not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(appointment, field, value)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "that doctor already has an appointment at that time",
        ) from None
    db.refresh(appointment)
    return _to_out(appointment)


@router.delete("/{appointment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_appointment(appointment_id: int, db: Session = Depends(get_db)) -> None:
    appointment = db.get(Appointment, appointment_id)
    if appointment is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "appointment not found")
    db.delete(appointment)
    db.commit()
