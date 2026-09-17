defmodule Pronotex.Pronote.Crypto do
  @moduledoc false
  alias Pronotex.Pronote.Error

  def md5(bytes), do: :crypto.hash(:md5, bytes)
  def hex(bytes), do: Base.encode16(bytes, case: :lower)
  def unhex(bytes), do: Base.decode16!(bytes, case: :mixed)

  def encrypt(bytes, key, iv) do
    padding = 16 - rem(byte_size(bytes), 16)

    :crypto.crypto_one_time(
      :aes_128_cbc,
      key,
      iv,
      bytes <> :binary.copy(<<padding>>, padding),
      true
    )
  end

  def decrypt(bytes, key, iv) do
    if byte_size(bytes) == 0 or rem(byte_size(bytes), 16) != 0, do: raise(Error.new(:protocol))
    padded = :crypto.crypto_one_time(:aes_128_cbc, key, iv, bytes, false)
    padding = :binary.last(padded)

    if padding not in 1..16 or
         binary_part(padded, byte_size(padded) - padding, padding) !=
           :binary.copy(<<padding>>, padding) do
      raise Error.new(:protocol)
    end

    binary_part(padded, 0, byte_size(padded) - padding)
  end

  def authentication_key(username, password, identification) do
    username =
      if case_insensitive?(identification["modeCompLog"]),
        do: String.downcase(username),
        else: username

    password =
      if case_insensitive?(identification["modeCompMdp"]),
        do: String.downcase(password),
        else: password

    digest = :crypto.hash(:sha256, (identification["alea"] || "") <> password) |> Base.encode16()
    md5(username <> digest)
  end

  # PRONOTE uses numeric comparison modes. Unlike Python/JavaScript, 0 is truthy
  # in Elixir, so it must never be used directly as an `if` condition.
  defp case_insensitive?(mode) when is_integer(mode), do: mode > 0
  defp case_insensitive?(mode), do: mode == true

  def deflate(bytes) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, 6, :deflated, -15, 8, :default)
      :zlib.deflate(z, bytes, :finish) |> IO.iodata_to_binary()
    after
      :zlib.close(z)
    end
  end

  def inflate(bytes) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      :zlib.inflate(z, bytes) |> IO.iodata_to_binary()
    after
      :zlib.close(z)
    end
  end

  # PRONOTE's legacy RSA public key (same as pronotepy / eleve.js).
  def rsa_encrypt(bytes) do
    modulus =
      130_337_874_517_286_041_778_445_012_253_514_395_801_341_480_334_668_979_416_920_989_365_464_528_904_618_150_245_388_048_105_865_059_387_076_357_492_684_573_172_203_245_221_386_376_405_947_824_377_827_224_846_860_699_130_638_566_643_129_067_735_803_555_082_190_977_267_155_957_271_492_183_684_665_050_351_182_476_506_458_843_580_431_717_209_261_903_043_895_605_014_125_081_521_285_387_341_454_154_194_253_026_277

    :public_key.encrypt_public(bytes, {:RSAPublicKey, modulus, 65_537},
      rsa_padding: :rsa_pkcs1_padding
    )
  end
end
