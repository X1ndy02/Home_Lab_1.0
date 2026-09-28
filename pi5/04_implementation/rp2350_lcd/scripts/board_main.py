from machine import Pin, SPI, PWM
import framebuf
import sys
import time

BL = 21
DC = 16
RST = 20
MOSI = 19
SCK = 18
CS = 17
SHOW_IPS = True

class LCD_1inch47(framebuf.FrameBuffer):
    def __init__(self):
        self.width = 172
        self.height = 320
        self.cs = Pin(CS, Pin.OUT)
        self.rst = Pin(RST, Pin.OUT)
        self.cs(1)
        self.spi = SPI(0, 100_000_000, polarity=0, phase=0, sck=Pin(SCK), mosi=Pin(MOSI), miso=None)
        self.dc = Pin(DC, Pin.OUT)
        self.dc(1)
        self.buffer = bytearray(self.height * self.width * 2)
        super().__init__(self.buffer, self.width, self.height, framebuf.RGB565)
        self.init_display()

        self.BLACK = 0x0000
        self.WHITE = 0xFFFF
        self.CYAN = 0x07FF
        self.YELLOW = 0xFFE0
        # Text color selected from shade grid: #8 = green level 28 -> 0x0380.
        self.TEXT = 0x0380
        # Keep these for future tweaks if needed.
        self.GREEN = 0x07E0
        self.RED = 0xF800

        self._glyph_buf = bytearray(8)
        self._glyph_fb = framebuf.FrameBuffer(self._glyph_buf, 8, 8, framebuf.MONO_HLSB)

    def write_cmd(self, cmd):
        self.cs(1); self.dc(0); self.cs(0); self.spi.write(bytearray([cmd])); self.cs(1)

    def write_data(self, buf):
        self.cs(1); self.dc(1); self.cs(0); self.spi.write(bytearray([buf])); self.cs(1)

    def init_display(self):
        self.rst(1); time.sleep_ms(10)
        self.rst(0); time.sleep_ms(10)
        self.rst(1); time.sleep_ms(120)

        # locked rotation (no BGR swap)
        self.write_cmd(0x36); self.write_data(0xC0)
        self.write_cmd(0x3A); self.write_data(0x05)
        self.write_cmd(0xB2)
        for x in (0x0C, 0x0C, 0x00, 0x33, 0x33): self.write_data(x)
        self.write_cmd(0xB7); self.write_data(0x35)
        self.write_cmd(0xC0); self.write_data(0x2C)
        self.write_cmd(0xC2); self.write_data(0x01)
        self.write_cmd(0xC3); self.write_data(0x13)
        self.write_cmd(0xC4); self.write_data(0x20)
        self.write_cmd(0xC6); self.write_data(0x0F)
        self.write_cmd(0xD0); self.write_data(0xA4); self.write_data(0xA1)
        self.write_cmd(0xE0)
        for x in (0xF0,0x00,0x04,0x04,0x05,0x29,0x33,0x3E,0x38,0x12,0x12,0x28,0x30): self.write_data(x)
        self.write_cmd(0xE1)
        for x in (0xF0,0x07,0x0A,0x0D,0x0B,0x07,0x28,0x33,0x3E,0x36,0x14,0x14,0x29,0x23): self.write_data(x)
        self.write_cmd(0x21)
        self.write_cmd(0x11); time.sleep_ms(120)
        self.write_cmd(0x29)

    def show(self):
        self.write_cmd(0x2A)
        self.write_data(0x00); self.write_data(0x22); self.write_data(0x00); self.write_data(0xCD)
        self.write_cmd(0x2B)
        self.write_data(0x00); self.write_data(0x00); self.write_data(0x01); self.write_data(0x3F)
        self.write_cmd(0x2C)
        self.cs(1); self.dc(1); self.cs(0); self.spi.write(self.buffer); self.cs(1)

    # 1.25x text (10x10) for slightly bigger readability
    def text125(self, s, x, y, color):
        cx = x
        for ch in s:
            self._glyph_fb.fill(0)
            self._glyph_fb.text(ch, 0, 0, 1)
            for dy in range(10):
                sy = (dy * 8) // 10
                for dx in range(10):
                    sx = (dx * 8) // 10
                    if self._glyph_fb.pixel(sx, sy):
                        self.pixel(cx + dx, y + dy, color)
            cx += 10


def parse_line(line):
    d = {}
    for part in line.strip().split(';'):
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        d[k.strip()] = v.strip()
    return d


def parse_service(val):
    if ':' not in val:
        return ('-', '--')
    n, p = val.rsplit(':', 1)
    n = n.strip()[:12] if n.strip() else '-'
    p = p.strip()[:5] if p.strip() else '--'
    return (n, p)

def format_line(name, pct, width=15):
    pct_text = pct + '%'
    # Keep at least 1 space between name and percent.
    max_name = max(1, width - len(pct_text) - 1)
    name = name[:max_name]
    spaces = width - len(name) - len(pct_text)
    if spaces < 1:
        spaces = 1
    return name + (' ' * spaces) + pct_text

def center_x_text125(text, min_x=6):
    width = len(text) * 10  # 10px per char at 1.25x
    x = (172 - width) // 2
    if x < min_x:
        x = min_x
    return x

def center_x_text(text, min_x=6):
    width = len(text) * 8  # 8px per char at 1x
    x = (172 - width) // 2
    if x < min_x:
        x = min_x
    return x

def parse_ip(val):
    val = (val or '').strip()
    if not val or val == '--':
        return ('', '')
    if ':' in val and '.' in val:
        tag, rest = val.split(':', 1)
        if tag.isalpha() and len(tag) <= 3:
            return (tag, rest)
    return ('IP', val)


def format_ip_line(tag, ip, width=18):
    if not ip:
        return ''
    tag = tag.strip().upper()
    if tag == 'E':
        tag = 'ETH'
    elif tag == 'W':
        tag = 'WRL'
    elif tag == 'ZT':
        tag = 'ZT'
    else:
        tag = (tag or 'IP')[:3]
    # Right-align IP; keep at least one space between tag and IP.
    max_ip = max(1, width - len(tag) - 1)
    ip = ip[:max_ip]
    spaces = width - len(tag) - len(ip)
    if spaces < 1:
        spaces = 1
    return tag + (' ' * spaces) + ip

def parse_color(val, fallback):
    if val is None:
        return fallback
    val = str(val).strip()
    if not val or val == '--':
        return fallback
    try:
        if val.lower().startswith('0x'):
            return int(val, 16)
        return int(val)
    except ValueError:
        return fallback


def draw_wait(lcd):
    lcd.fill(lcd.BLACK)
    title = 'SYSTEM'
    lcd.text125(title, center_x_text125(title), 6, lcd.TEXT)
    label = 'STATS'
    lcd.text125(label, center_x_text125(label), 22, lcd.TEXT)
    lcd.text125('WAITING DATA', 6, 42, lcd.TEXT)
    lcd.show()


def draw_stats(lcd, s):
    col = parse_color(s.get('col', ''), lcd.TEXT)
    host = s.get('host', 'SYSTEM')[:16]
    cpu = s.get('cpu', '--')
    ram = s.get('ram', '--')
    ups = s.get('ups', '--')
    ping = s.get('ping', '--')
    temp = s.get('temp', '--')
    thr = s.get('thr', '--')

    tshort = temp.split('.', 1)[0] if '.' in temp else temp

    s1n, s1p = parse_service(s.get('s1', '-:--'))
    s2n, s2p = parse_service(s.get('s2', '-:--'))
    s3n, s3p = parse_service(s.get('s3', '-:--'))
    s4n, s4p = parse_service(s.get('s4', '-:--'))
    s5n, s5p = parse_service(s.get('s5', '-:--'))
    if SHOW_IPS:
        ip1t, ip1 = parse_ip(s.get('ip1', '--'))
        ip2t, ip2 = parse_ip(s.get('ip2', ''))
        ip3t, ip3 = parse_ip(s.get('ip3', ''))
    tm = s.get('tm', '--:--')
    dt = s.get('dt', '---- -- --')

    lcd.fill(lcd.BLACK)

    lcd.text125(host, center_x_text125(host), 6, col)
    lcd.hline(4, 26, 164, col)
    stats_label = 'STATS:'
    lcd.text125(stats_label, center_x_text125(stats_label), 30, col)

    lcd.text125(('CPU ' + cpu + '%  RAM ' + ram + '%')[:15], 6, 50, col)
    ups_disp = ups.split('.', 1)[0] if '.' in ups else ups
    lcd.text125(('UPS ' + ups_disp + '%  P ' + ping + 'ms')[:15], 6, 68, col)
    lcd.text125(('TMP ' + tshort + 'C  THR ' + thr)[:15], 6, 86, col)

    lcd.hline(4, 110, 164, col)
    label = 'CPU LOAD:'
    lcd.text125(label, center_x_text125(label), 122, col)

    lcd.text125(format_line(s1n, s1p), 6, 142, col)
    lcd.text125(format_line(s2n, s2p), 6, 158, col)
    lcd.text125(format_line(s3n, s3p), 6, 174, col)
    lcd.text125(format_line(s4n, s4p), 6, 190, col)
    lcd.text125(format_line(s5n, s5p), 6, 206, col)
    lcd.hline(4, 230, 164, col)

    if SHOW_IPS:
        # IPs pinned to the bottom
        line1 = format_ip_line(ip1t, ip1)
        line2 = format_ip_line(ip2t, ip2)
        line3 = format_ip_line(ip3t, ip3)
        if line1:
            lcd.text(line1, 8, 242, col)
        if line2:
            lcd.text(line2, 8, 254, col)
        if line3:
            lcd.text(line3, 8, 266, col)
    lcd.text(dt, 8, 288, col)
    lcd.text125(tm, 8, 300, col)
    lcd.show()


pwm = PWM(Pin(BL))
pwm.freq(1000)
pwm.duty_u16(32768)

lcd = LCD_1inch47()
draw_wait(lcd)

while True:
    line = sys.stdin.readline()
    if not line:
        time.sleep_ms(50)
        continue
    stats = parse_line(line)
    if stats:
        draw_stats(lcd, stats)
