from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Doctor
from app.schemas import DoctorCreate, DoctorOut

router = APIRouter(prefix="/api/doctors", tags=["doctors"])


@router.get("", response_model=list[DoctorOut])
def list_doctors(db: Session = Depends(get_db)) -> list[Doctor]:
    return list(db.scalars(select(Doctor).order_by(Doctor.name)))


@router.post("", response_model=DoctorOut, status_code=status.HTTP_201_CREATED)
def create_doctor(payload: DoctorCreate, db: Session = Depends(get_db)) -> Doctor:
    doctor = Doctor(**payload.model_dump())
    db.add(doctor)
    db.commit()
    db.refresh(doctor)
    return doctor


@router.get("/{doctor_id}", response_model=DoctorOut)
def get_doctor(doctor_id: int, db: Session = Depends(get_db)) -> Doctor:
    doctor = db.get(Doctor, doctor_id)
    if doctor is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "doctor not found")
    return doctor
