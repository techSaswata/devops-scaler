from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Patient
from app.schemas import PatientCreate, PatientOut

router = APIRouter(prefix="/api/patients", tags=["patients"])


@router.get("", response_model=list[PatientOut])
def list_patients(db: Session = Depends(get_db)) -> list[Patient]:
    return list(db.scalars(select(Patient).order_by(Patient.name)))


@router.post("", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
def create_patient(payload: PatientCreate, db: Session = Depends(get_db)) -> Patient:
    patient = Patient(
        name=payload.name,
        phone=payload.phone,
        email=str(payload.email) if payload.email else None,
    )
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return patient


@router.get("/{patient_id}", response_model=PatientOut)
def get_patient(patient_id: int, db: Session = Depends(get_db)) -> Patient:
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "patient not found")
    return patient
