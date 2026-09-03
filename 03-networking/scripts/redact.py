#!/usr/bin/env python3
"""
Redact personally-identifying network details before committing to a PUBLIC repo.

What gets masked and why:
  - MAC addresses      -> these identify physical devices, including OTHER PEOPLE's
                          devices picked up in the ARP cache of a shared network.
  - the public IP      -> identifies the submitter's internet connection/location.
  - the ISP router's reverse-DNS hostname.
Local RFC1918-style addresses and the structure of every command's output are kept
intact, so the exercise still demonstrates exactly what each command shows.
"""
import re, sys

PUBLIC_IP = "202.131.133.56"
ISP_HOST  = "wifi.height8tech.com"

mac_re = re.compile(r'\b([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}\b')

def redact(text: str) -> str:
    text = mac_re.sub("xx:xx:xx:xx:xx:xx", text)
    text = text.replace(PUBLIC_IP, "<redacted-public-ip>")
    text = text.replace(ISP_HOST, "<isp-router>")
    # the local /20 host addresses of neighbouring devices
    text = re.sub(r'\b100\.129\.(1[6-9][0-9]|1[0-9][0-9])\.(\d+)\b',
                  lambda m: f"100.129.{m.group(1)}.xxx", text)
    return text

if __name__ == "__main__":
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8", errors="replace") as f:
            original = f.read()
        cleaned = redact(original)
        with open(path, "w", encoding="utf-8") as f:
            f.write(cleaned)
        n = len(mac_re.findall(original))
        print(f"redacted {path}: {n} MAC addresses, public IP, ISP hostname")
