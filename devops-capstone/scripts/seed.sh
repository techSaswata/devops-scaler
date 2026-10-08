#!/usr/bin/env bash
# Populate a clinic with believable data, through the public API only.
#
# Seeding over HTTP rather than with SQL is deliberate: it exercises the same
# validation, the same constraints and the same error handling a real client
# would hit, so a broken endpoint fails here instead of looking fine until a
# human clicks it.
set -u
API="${API:-http://localhost:3000/api}"
post(){ curl -s -X POST "$API/$1" -H 'Content-Type: application/json' -d "$2"; }

echo "==> doctors"
for d in \
  '{"name":"Dr Aparna Rao","specialty":"Cardiology","room":"C-12"}' \
  '{"name":"Dr Imran Qureshi","specialty":"Dermatology","room":"D-04"}' \
  '{"name":"Dr Meera Nair","specialty":"Paediatrics","room":"P-21"}' \
  '{"name":"Dr Vikram Sethi","specialty":"Orthopaedics","room":"O-07"}'
do post doctors "$d" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("   ", d["id"], d["name"])'
done

echo "==> patients"
for p in \
  '{"name":"Rahul Menon","phone":"+91-9000000001","email":"rahul@example.com"}' \
  '{"name":"Sneha Iyer","phone":"+91-9000000002","email":"sneha@example.com"}' \
  '{"name":"Arjun Bhat","phone":"+91-9000000003"}' \
  '{"name":"Fatima Sheikh","phone":"+91-9000000004","email":"fatima@example.com"}' \
  '{"name":"Joseph Thomas","phone":"+91-9000000005"}'
do post patients "$p" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("   ", d["id"], d["name"])'
done

echo "==> appointments"
python3 - "$API" <<'PY'
import json, subprocess, sys
from datetime import datetime, timedelta, timezone

api = sys.argv[1]
now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)

# (patient, doctor, hours from now, status, reason)
plan = [
    (1, 1,   2, "scheduled", "Chest pain follow-up"),
    (2, 2,   4, "scheduled", "Eczema review"),
    (3, 3,   6, "scheduled", "6-month vaccination"),
    (4, 1,  26, "scheduled", "ECG results"),
    (5, 4,  28, "scheduled", "Knee MRI discussion"),
    (1, 3,  50, "scheduled", "Paediatric referral"),
    (2, 1, -24, "completed", "Blood pressure check"),
    (3, 2, -48, "completed", "Patch test"),
    (4, 4, -72, "no_show",   "Post-op review"),
    (5, 2, -96, "cancelled", "Mole screening"),
]

for pid, did, hrs, status, reason in plan:
    body = {
        "patient_id": pid, "doctor_id": did,
        "scheduled_at": (now + timedelta(hours=hrs)).isoformat(),
        "duration_minutes": 30, "reason": reason,
    }
    out = subprocess.run(
        ["curl", "-s", "-X", "POST", f"{api}/appointments",
         "-H", "Content-Type: application/json", "-d", json.dumps(body)],
        capture_output=True, text=True).stdout
    created = json.loads(out)
    if status != "scheduled":
        subprocess.run(
            ["curl", "-s", "-X", "PUT", f"{api}/appointments/{created['id']}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"status": status})], capture_output=True)
    print(f"    {created['id']:>2}  {reason[:28]:<28} {status}")
PY

echo "==> stats"
curl -s "$API/appointments/stats" | python3 -m json.tool
