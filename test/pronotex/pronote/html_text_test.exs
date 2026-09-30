defmodule Pronotex.Pronote.HTMLTextTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.HTMLText

  test "preserves a blank line before the signature" do
    html =
      "Bonjour,<br>Première phrase.<br>Deuxième phrase.<br><br>Bien cordialement.<br>M. Martin"

    assert HTMLText.parse(html) ==
             "Bonjour,\nPremière phrase.\nDeuxième phrase.\n\nBien cordialement.\nM. Martin"
  end

  test "nested blocks do not multiply line breaks and empty blocks remain visible" do
    html =
      "<div><p>Bonjour<br></p></div>\n<div><br></div><div>Merci</div><div>&nbsp;</div><div>Signature</div>"

    assert HTMLText.parse(html) == "Bonjour\n\nMerci\n\nSignature"
  end

  test "HTML source whitespace wraps normally and scripts remain excluded" do
    assert HTMLText.parse(
             "<p>Une phrase\n sur deux lignes source.</p><script>secret</script><p>Suite</p>"
           ) ==
             "Une phrase sur deux lignes source.\nSuite"
  end
end
