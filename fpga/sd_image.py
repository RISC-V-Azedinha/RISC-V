"""
Grava um programa no cartão microSD pelo computador, no mesmo formato que o bootloader usa
(o caminho alternativo ao `make upload SAVE=1`).

    bloco 1     cabeçalho { "RVSD", tamanho, checksum, ~"RVSD" } (little endian)
    bloco 2...  o programa

Os blocos ficam no espaço livre entre o MBR e a primeira partição, então o cartão continua
funcionando normalmente no computador. O script confere a tabela de partições antes de gravar.

Uso (Linux; o dispositivo é o cartão inteiro, ex.: /dev/sdb ou /dev/mmcblk0, não uma partição):
    sudo python3 fpga/sd_image.py /dev/sdX build/fpga/bin/blink.bin
    sudo python3 fpga/sd_image.py /dev/sdX --erase
"""

import argparse
import os
import struct
import sys

BLOCK        = 512
HDR_BLOCK    = 1
SD_MAGIC     = 0x44535652                  # "RVSD"
USER_APP_MAX = 256 * 1024 - 0x800          # A RAM começa o app em 0x80000800


def checksum(data: bytes) -> int:
    """Soma com rotação, palavra a palavra (o mesmo cálculo do bootloader)."""
    data = data + bytes(-len(data) % 4)
    total = 0
    for (word,) in struct.iter_unpack('<I', data):
        total = ((((total << 1) | (total >> 31)) & 0xFFFFFFFF) + word) & 0xFFFFFFFF
    return total


def free_blocks(mbr: bytes) -> int:
    """Blocos antes da primeira partição (o espaço que o bootloader pode usar)."""
    if mbr[0] in (0xEB, 0xE9):
        return 0                            # FAT direto no bloco 0, sem tabela de partições
    if mbr[510:512] != b'\x55\xAA':
        return 1 << 32                      # Sem tabela de partições: cartão livre
    starts = []
    for i in range(4):
        entry = mbr[0x1BE + 16 * i: 0x1BE + 16 * (i + 1)]
        if entry[4] != 0:
            starts.append(struct.unpack_from('<I', entry, 8)[0])
    return min(starts, default=1 << 32)


def main():
    parser = argparse.ArgumentParser(description='Grava um programa no cartão microSD para o bootloader do SoC')
    parser.add_argument('device', help='Cartão inteiro (ex.: /dev/sdb) ou um arquivo de imagem')
    parser.add_argument('binary', nargs='?', help='Programa (.bin) gerado pelo make sw-fpga')
    parser.add_argument('--erase', action='store_true', help='Apaga o programa do cartão')
    args = parser.parse_args()

    if not args.erase and not args.binary:
        parser.error('informe o programa (.bin) ou --erase')

    payload = b''
    if not args.erase:
        with open(args.binary, 'rb') as f:
            payload = f.read()
        if not 0 < len(payload) <= USER_APP_MAX:
            sys.exit(f'Erro: o programa tem {len(payload)} bytes (máximo {USER_APP_MAX}).')

    with open(args.device, 'r+b') as dev:
        mbr = dev.read(BLOCK)
        if len(mbr) < BLOCK:
            sys.exit('Erro: não foi possível ler o bloco 0 do cartão.')

        blocks = -(-len(payload) // BLOCK)
        limit = free_blocks(mbr)
        if HDR_BLOCK + 1 + blocks > limit:
            sys.exit(f'Erro: só há {max(limit - HDR_BLOCK - 1, 0)} blocos livres antes da primeira partição; '
                     f'o programa precisa de {blocks}.')

        # Invalida o cabeçalho, grava o programa e só então o cabeçalho novo
        dev.seek(HDR_BLOCK * BLOCK)
        dev.write(bytes(BLOCK))
        if args.erase:
            print('Programa apagado do cartão.')
            return

        dev.seek((HDR_BLOCK + 1) * BLOCK)
        dev.write(payload + bytes(blocks * BLOCK - len(payload)))
        header = struct.pack('<4I', SD_MAGIC, len(payload), checksum(payload), ~SD_MAGIC & 0xFFFFFFFF)
        dev.seek(HDR_BLOCK * BLOCK)
        dev.write(header + bytes(BLOCK - len(header)))
        dev.flush()
        os.fsync(dev.fileno())

    print(f'{args.binary}: {len(payload)} bytes gravados nos blocos {HDR_BLOCK}..{HDR_BLOCK + blocks} do cartão.')


if __name__ == '__main__':
    main()
