"""Doctors and patients."""


def test_create_and_list_doctor(client):
    created = client.post(
        "/api/doctors",
        json={"name": "Dr Imran Qureshi", "specialty": "Dermatology", "room": "D-4"},
    )
    assert created.status_code == 201
    assert created.json()["specialty"] == "Dermatology"

    listed = client.get("/api/doctors")
    assert listed.status_code == 200
    assert len(listed.json()) == 1


def test_create_patient_and_fetch_by_id(client):
    created = client.post(
        "/api/patients",
        json={"name": "Sneha Iyer", "phone": "+91-9000000002", "email": "sneha@example.com"},
    )
    assert created.status_code == 201
    pid = created.json()["id"]

    fetched = client.get(f"/api/patients/{pid}")
    assert fetched.status_code == 200
    assert fetched.json()["email"] == "sneha@example.com"


def test_patient_rejects_short_name(client):
    r = client.post("/api/patients", json={"name": "A", "phone": "+91-9000000003"})
    assert r.status_code == 422


def test_missing_patient_is_404(client):
    assert client.get("/api/patients/9999").status_code == 404
