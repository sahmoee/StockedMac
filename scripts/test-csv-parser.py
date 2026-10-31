#!/usr/bin/env python3
"""Compile exact production parser with the pure guard helper; no UI/user data."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'StockedMac/Core/MacRecipeCSV.swift').read_text()
start = source.index('    static func parseCSVRows(')
end = source.index('\n    /// What counts as', start)
parser = source[start:end]
checks = r'''
@main struct Checks {
    static func main() {
        for newline in ["\n", "\r\n", "\r"] {
            let rows = MacRecipeCSV.parseCSVRows("\u{FEFF}title,id" + newline + "first,1" + newline + "second,2" + newline)
            precondition(rows == [["title", "id"], ["first", "1"], ["second", "2"]])
        }
        let original = "'=literal,with\r\nlines\""
        let rows = MacRecipeCSV.parseCSVRows("title\r\n" + MacCSVInterchange.escape(original) + "\r\n")
        precondition(rows.count == 2 && MacCSVInterchange.unguard(rows[1][0]) == original)
        print("4 production CSV parser checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='stockedmac-csv-') as temp:
    path = Path(temp)
    fixture = path / 'Checks.swift'
    fixture.write_text('import Foundation\nenum MacRecipeCSV {\n' + parser + '\n}\n' + checks)
    binary = path / 'checks'
    subprocess.run(['swiftc', str(root/'StockedMac/Core/MacCSVInterchange.swift'), str(fixture), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
