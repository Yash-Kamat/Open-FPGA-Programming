#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/ioctl.h>

/* Must match the definition in the kernel driver */
#define FPGA_SET_REG  _IOW('F', 1, uint8_t)

/*
 * write_reg — write one byte to a FPGA register.
 * Uses the 2-byte [reg, value] write path in the driver.
 */
void write_reg(int fd, uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = { reg, value };

    if (write(fd, buf, 2) != 2)
        perror("write_reg: write");
    else
        printf("Written: reg 0x%02X = 0x%02X\n", reg, value);
}

/*
 * read_reg — read one byte from a FPGA register.
 *
 * Uses pread() so the register address is sent atomically as the file
 * offset; this eliminates the two-syscall race that caused the original
 * bug (write-to-select-reg then read could be interleaved, leaving the
 * kernel's current_reg pointing at the wrong register).
 */
uint8_t read_reg(int fd, uint8_t reg)
{
    uint8_t data = 0;

    /*
     * pread(fd, buf, count, offset):
     *   offset → file position → treated as register address by dev_read()
     * This is a single atomic syscall — no race window.
     */
    if (pread(fd, &data, 1, (off_t)reg) != 1)
        perror("read_reg: pread");

    return data;
}

/*
 * read_reg_ioctl — alternative read using ioctl to set the register.
 * Kept here for reference / backwards-compatibility testing.
 * Prefer read_reg() (pread path) in production.
 */
uint8_t read_reg_ioctl(int fd, uint8_t reg)
{
    uint8_t data = 0;

    if (ioctl(fd, FPGA_SET_REG, (unsigned long)reg) < 0) {
        perror("read_reg_ioctl: ioctl");
        return 0;
    }
    if (read(fd, &data, 1) != 1)
        perror("read_reg_ioctl: read");

    return data;
}

int main(void)
{
    int     fd;
    uint8_t val0, val1;

    fd = open("/dev/i2c_fpga", O_RDWR);
    if (fd < 0) {
        perror("open /dev/i2c_fpga");
        return 1;
    }

    printf("---- FPGA I2C TEST ----\n");

    /* -------- WRITE BOTH REGISTERS -------- */
    write_reg(fd, 0x00, 0x00);
    write_reg(fd, 0x01, 0x02);

    /* -------- READ BACK USING pread (recommended) -------- */
    val0 = read_reg(fd, 0x00);
    val1 = read_reg(fd, 0x01);

    printf("\n---- READ BACK (pread path) ----\n");
    printf("reg 0x00 = 0x%02X  (expect 0xAA) %s\n", val0,
           val0 == 0xAA ? "OK" : "MISMATCH");
    printf("reg 0x01 = 0x%02X  (expect 0x55) %s\n", val1,
           val1 == 0x55 ? "OK" : "MISMATCH");

    /* -------- READ BACK USING ioctl (legacy path) -------- */
    val0 = read_reg_ioctl(fd, 0x00);
    val1 = read_reg_ioctl(fd, 0x01);

    printf("\n---- READ BACK (ioctl path) ----\n");
    printf("reg 0x00 = 0x%02X  (expect 0xAA) %s\n", val0,
           val0 == 0xAA ? "OK" : "MISMATCH");
    printf("reg 0x01 = 0x%02X  (expect 0x55) %s\n", val1,
           val1 == 0x55 ? "OK" : "MISMATCH");

    close(fd);
    return 0;
}
