defmodule Pronotex.Pronote.CryptoTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.{Crypto, Error}

  test "AES-CBC matches the first block of the NIST SP 800-38A vector" do
    key = Base.decode16!("2B7E151628AED2A6ABF7158809CF4F3C")
    iv = Base.decode16!("000102030405060708090A0B0C0D0E0F")
    plain = Base.decode16!("6BC1BEE22E409F96E93D7E117393172A")
    encrypted = Crypto.encrypt(plain, key, iv)
    assert binary_part(encrypted, 0, 16) == Base.decode16!("7649ABAC8119B246CEE98E9B12E9197D")
    assert byte_size(encrypted) == 32
    assert Crypto.decrypt(encrypted, key, iv) == plain
  end

  test "rejects invalid PKCS7 padding" do
    bytes = :crypto.crypto_one_time(:aes_128_cbc, <<0::128>>, <<0::128>>, <<0::128>>, true)
    assert_raise Error, fn -> Crypto.decrypt(bytes, <<0::128>>, <<0::128>>) end
  end

  test "numeric comparison flags 0/0 preserve the server's case rules" do
    identification = %{"modeCompLog" => 0, "modeCompMdp" => 0, "alea" => "salt"}

    assert Crypto.authentication_key("Parent", "PaSsWord-TEST", identification) ==
             Base.decode16!("F40DCFCD9F6E71F8DC1492A57BDF1C3D")
  end

  test "numeric comparison flags 1/0 preserve the server's case rules" do
    identification = %{"modeCompLog" => 1, "modeCompMdp" => 0, "alea" => "salt"}

    assert Crypto.authentication_key("Parent", "PaSsWord-TEST", identification) ==
             Base.decode16!("CABFE252BD95C4D3FE1C588CF0400F46")
  end

  test "numeric comparison flags 0/1 preserve the server's case rules" do
    identification = %{"modeCompLog" => 0, "modeCompMdp" => 1, "alea" => "salt"}

    assert Crypto.authentication_key("Parent", "PaSsWord-TEST", identification) ==
             Base.decode16!("A79BB11AA57F7934570995DEFFC1A7C1")
  end

  test "numeric comparison flags 1/1 preserve the server's case rules" do
    identification = %{"modeCompLog" => 1, "modeCompMdp" => 1, "alea" => "salt"}

    assert Crypto.authentication_key("Parent", "PaSsWord-TEST", identification) ==
             Base.decode16!("D352A4E6A1597BB09E1F8629E08EF008")
  end
end
