#!/usr/bin/env python3
"""Compile the production invite parser and check the wire contract without secrets."""
import pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'StockedMac/Core/MacHouseholdSync.swift').read_text()
parser = source[source.index('nonisolated enum MacHouseholdInvite'):].replace('nonisolated enum', 'enum')
checks = '''
let secret = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcdefg"
let good = MacHouseholdInvite.parse("Join: https://sowensstudios.com/join/ABCD2345#invite=" + secret)
precondition(good.code == "ABCD2345" && good.invite == secret)
precondition(MacHouseholdInvite.parse("ABCD2345").invite == nil)
precondition(MacHouseholdInvite.parse("ABCD23456#invite=" + secret).code.isEmpty)
precondition(MacHouseholdInvite.parse("ABCD2345#invite=" + secret + "!").invite == nil)
precondition(MacHouseholdInvite.parse("ABCD2345#invite=" + String(repeating: "a", count: 129)).invite == nil)
precondition(MacHouseholdInvite.parse("ABCD2345#invite=" + String(repeating: "é", count: 43)).invite == nil)
print("6 production invitation parser checks passed")
'''
with tempfile.TemporaryDirectory(prefix='stockedmac-invite-') as temp:
    path = pathlib.Path(temp)
    (path / 'main.swift').write_text('import Foundation\n' + parser + checks)
    subprocess.run(['/Library/Developer/CommandLineTools/usr/bin/swiftc', '-sdk', '/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk', str(path/'main.swift'), '-o', str(path/'checks')], check=True)
    subprocess.run([str(path/'checks')], check=True)
