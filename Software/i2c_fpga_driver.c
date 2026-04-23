#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/i2c.h>
#include <linux/uaccess.h>
#include <linux/cdev.h>

#define DEVICE_NAME "i2c_fpga"
#define CLASS_NAME  "i2c_fpga_class"
#define I2C_BUS     1
#define FPGA_ADDR   0x42

/* ioctl command: set register address */
#define FPGA_SET_REG  _IOW('F', 1, uint8_t)

static struct i2c_adapter *adapter;
static struct i2c_client  *client;
static int                 major;
static struct class       *cls;
static struct cdev         cdev;

/* ---------------- WRITE (i2cset equivalent) ---------------- */
/*
 * Supports two calling conventions:
 *   1) 2-byte write  [reg, value]  — legacy, sets register + data in one call
 *   2) pwrite(fd, &val, 1, reg)   — register comes from file offset
 */
static ssize_t dev_write(struct file *file, const char __user *buf,
                         size_t len, loff_t *offset)
{
    u8 data[2];

    if (len == 1) {
        /* Value-only write: register address carried in file offset (pwrite) */
        data[0] = (u8)(*offset);
        if (copy_from_user(&data[1], buf, 1))
            return -EFAULT;
        if (i2c_master_send(client, data, 2) < 0)
            return -EIO;
        printk(KERN_INFO "FPGA: Write reg 0x%x = 0x%x\n", data[0], data[1]);
        return 1;
    }

    if (len == 2) {
        /* Full [reg, value] pair supplied by caller */
        if (copy_from_user(data, buf, 2))
            return -EFAULT;
        if (i2c_master_send(client, data, 2) < 0)
            return -EIO;
        printk(KERN_INFO "FPGA: Write reg 0x%x = 0x%x\n", data[0], data[1]);
        return 2;
    }

    return -EINVAL;
}

/* ---------------- READ (i2cget equivalent) ---------------- */
/*
 * Register address is taken from the file offset so that pread() can be
 * used from userspace:  pread(fd, &val, 1, reg_addr)
 * This avoids the two-syscall race (write-to-select-reg then read).
 */
static ssize_t dev_read(struct file *file, char __user *buf,
                        size_t len, loff_t *offset)
{
    u8 reg  = (u8)(*offset);   /* register address from file offset */
    u8 data = 0;
    struct i2c_msg msgs[2];
    int ret;

    /* Combined write-register-address + read-data transaction */
    msgs[0].addr  = client->addr;
    msgs[0].flags = 0;          /* write phase */
    msgs[0].len   = 1;
    msgs[0].buf   = &reg;

    msgs[1].addr  = client->addr;
    msgs[1].flags = I2C_M_RD;  /* read phase */
    msgs[1].len   = 1;
    msgs[1].buf   = &data;

    ret = i2c_transfer(client->adapter, msgs, 2);
    if (ret != 2) {
        printk(KERN_ERR "FPGA: I2C transfer failed: %d\n", ret);
        return -EIO;
    }

    if (copy_to_user(buf, &data, 1))
        return -EFAULT;

    printk(KERN_INFO "FPGA: Read reg 0x%x = 0x%x\n", reg, data);
    return 1;
}

/* ---------------- IOCTL — set register address ---------------- */
/*
 * BUG FIX: previously wrote to buffer[0] instead of current_reg.
 * Now stores the register address so a plain read() after ioctl() works.
 * Prefer pread() in new code; ioctl kept for backwards compatibility.
 */
static long dev_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    if (cmd == FPGA_SET_REG) {
        /* Store as file offset so dev_read picks it up consistently */
        file->f_pos = (loff_t)(arg & 0xFF);
        printk(KERN_INFO "FPGA: ioctl set reg = 0x%lx\n", arg & 0xFF);
        return 0;
    }
    return -ENOTTY;
}

static struct file_operations fops = {
    .owner          = THIS_MODULE,
    .write          = dev_write,
    .read           = dev_read,
    .unlocked_ioctl = dev_ioctl,
};

/* ---------------- INIT ---------------- */
static int __init i2c_driver_init(void)
{
    dev_t dev;
    int   ret;

    printk(KERN_INFO "FPGA I2C driver init\n");

    adapter = i2c_get_adapter(I2C_BUS);
    if (!adapter)
        return -ENODEV;

    client = i2c_new_dummy_device(adapter, FPGA_ADDR);
    if (IS_ERR(client)) {
        i2c_put_adapter(adapter);
        return PTR_ERR(client);
    }

    ret = alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME);
    if (ret < 0)
        goto err_chrdev;

    major = MAJOR(dev);
    cdev_init(&cdev, &fops);

    ret = cdev_add(&cdev, dev, 1);
    if (ret < 0)
        goto err_cdev;

    cls = class_create(CLASS_NAME);
    if (IS_ERR(cls)) {
        ret = PTR_ERR(cls);
        goto err_class;
    }

    if (IS_ERR(device_create(cls, NULL, dev, NULL, DEVICE_NAME))) {
        ret = -ENOMEM;
        goto err_device;
    }

    printk(KERN_INFO "FPGA: Device created: /dev/%s\n", DEVICE_NAME);
    return 0;

err_device:
    class_destroy(cls);
err_class:
    cdev_del(&cdev);
err_cdev:
    unregister_chrdev_region(dev, 1);
err_chrdev:
    i2c_unregister_device(client);
    i2c_put_adapter(adapter);
    return ret;
}

/* ---------------- EXIT ---------------- */
static void __exit i2c_driver_exit(void)
{
    dev_t dev = MKDEV(major, 0);

    device_destroy(cls, dev);
    class_destroy(cls);
    cdev_del(&cdev);
    unregister_chrdev_region(dev, 1);
    i2c_unregister_device(client);
    i2c_put_adapter(adapter);

    printk(KERN_INFO "FPGA I2C driver removed\n");
}

module_init(i2c_driver_init);
module_exit(i2c_driver_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("You");
MODULE_DESCRIPTION("I2C FPGA driver (i2cget/i2cset equivalent) — fixed");
