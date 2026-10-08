"""Appointments: the full CRUD cycle, the booking conflict, and the stats."""
from datetime import datetime, timedelta, timezone


def _slot(hours: int = 24) -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).isoformat()


def test_full_crud_cycle(client, seeded):
    created = client.post(
        "/api/appointments",
        json={**seeded, "scheduled_at": _slot(), "reason": "Chest pain review"},
    )
    assert created.status_code == 201
    appt = created.json()
    assert appt["status"] == "scheduled"
    assert appt["doctor_name"] == "Dr Aparna Rao"

    aid = appt["id"]
    assert client.get(f"/api/appointments/{aid}").status_code == 200

    updated = client.put(f"/api/appointments/{aid}", json={"status": "completed"})
    assert updated.status_code == 200
    assert updated.json()["status"] == "completed"

    assert client.delete(f"/api/appointments/{aid}").status_code == 204
    assert client.get(f"/api/appointments/{aid}").status_code == 404


def test_double_booking_a_doctor_is_409(client, seeded):
    when = _slot(48)
    first = client.post("/api/appointments", json={**seeded, "scheduled_at": when})
    assert first.status_code == 201

    second = client.post("/api/appointments", json={**seeded, "scheduled_at": when})
    assert second.status_code == 409
    assert "already has an appointment" in second.json()["detail"]


def test_cancelling_frees_the_slot_but_keeps_the_record(client, seeded):
    when = _slot(72)
    first = client.post("/api/appointments", json={**seeded, "scheduled_at": when}).json()
    client.put(f"/api/appointments/{first['id']}", json={"status": "cancelled"})

    # The index excludes cancelled rows, so the slot is bookable again...
    rebooked = client.post("/api/appointments", json={**seeded, "scheduled_at": when})
    assert rebooked.status_code == 201
    # ...and the cancelled appointment is still on file.
    assert client.get(f"/api/appointments/{first['id']}").status_code == 200


def test_naive_datetime_is_rejected(client, seeded):
    r = client.post(
        "/api/appointments",
        json={**seeded, "scheduled_at": "2026-11-01T10:00:00"},   # no offset
    )
    assert r.status_code == 422


def test_appointment_for_unknown_doctor_is_404(client, seeded):
    r = client.post(
        "/api/appointments",
        json={"patient_id": seeded["patient_id"], "doctor_id": 4242, "scheduled_at": _slot()},
    )
    assert r.status_code == 404


def test_filter_by_status(client, seeded):
    client.post("/api/appointments", json={**seeded, "scheduled_at": _slot(10)})
    done = client.post("/api/appointments", json={**seeded, "scheduled_at": _slot(20)}).json()
    client.put(f"/api/appointments/{done['id']}", json={"status": "completed"})

    assert len(client.get("/api/appointments").json()) == 2
    assert len(client.get("/api/appointments?status=completed").json()) == 1


def test_stats_are_computed(client, seeded):
    client.post("/api/appointments", json={**seeded, "scheduled_at": _slot(5)})
    done = client.post("/api/appointments", json={**seeded, "scheduled_at": _slot(6)}).json()
    client.put(f"/api/appointments/{done['id']}", json={"status": "completed"})

    stats = client.get("/api/appointments/stats").json()
    assert stats["total"] == 2
    assert stats["scheduled"] == 1
    assert stats["completed"] == 1
    assert stats["upcoming_7_days"] == 1
    assert stats["doctors"] == 1 and stats["patients"] == 1
    assert stats["completion_rate"] == 100.0


def test_stats_on_an_empty_clinic_do_not_divide_by_zero(client):
    stats = client.get("/api/appointments/stats").json()
    assert stats["total"] == 0
    assert stats["completion_rate"] == 0.0
