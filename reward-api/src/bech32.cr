module Bech32
  CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

  def self.convert_hex_pub_key(hex_pub_key, output_format = "ed25519")
    raw_pub_key = hex_pub_key.hexbytes
    bits = convertbits(raw_pub_key, 8, 5)
    raise "Couldn't convert pubkey" unless bits

    bech32_pub_key = bech32_encode("#{output_format}_pk", bits)
    case output_format
    when "ed25519"
      bech32_pub_key
    when "jcliaddr"
      "jcliaddr_#{hex_pub_key}"
    else
      raise "Output format #{output_format} not supported!"
    end
  end

  def self.convertbits(data, from_bits, to_bits, pad = true)
    acc = 0
    bits = 0
    ret = [] of Int32
    maxv = (1 << to_bits) - 1
    max_acc = (1 << (from_bits + to_bits - 1)) - 1

    data.each do |value|
      return nil if value < 0 || (value >> from_bits) != 0
      acc = ((acc << from_bits) | value) & max_acc
      bits += from_bits
      while bits >= to_bits
        bits -= to_bits
        ret << ((acc >> bits) & maxv)
      end
    end

    if pad
      if bits
        ret << ((acc << (to_bits - bits)) & maxv)
      end
    elsif bits >= from_bits || ((acc << (to_bits - bits)) & maxv) != 0
      return nil
    end

    ret
  end

  def self.bech32_encode(hrp, data)
    checksum = bech32_create_checksum(hrp, data)
    combined = data + checksum
    hrp + "1" + combined.map { |c| CHARSET[c] }.join
  end

  def self.bech32_create_checksum(hrp, data)
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ 1
    (0..5).map { |i| (polymod >> 5 * (5 - i)) & 31 }
  end

  def self.bech32_hrp_expand(hrp)
    hrp.each_char.map { |x| x.ord >> 5 }.to_a + [0] + hrp.each_char.map { |x| x.ord & 31 }.to_a
  end

  GENERATOR = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

  def self.bech32_polymod(values)
    chk = 1

    values.each do |value|
      top = chk >> 25
      chk = (chk & 0x1ffffff) << 5 ^ value
      GENERATOR.each_with_index do |gen, i|
        chk ^= gen if ((top >> i) & 1) != 0
      end
    end

    chk
  end
end
