/**************************************************************************
 * Copyright (c) 2016, STMicroelectronics - All Rights Reserved

 License terms: BSD 3-clause "New" or "Revised" License.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software
 without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ****************************************************************************/

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/uaccess.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <linux/spi/spi.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/time.h>
#include <linux/uaccess.h>
#include <linux/platform_device.h>
#include <linux/version.h>
#include <linux/gpio.h>
#include <linux/regulator/consumer.h>

#include "stmvl53l5_i2c.h"
#include "stmvl53l5_spi.h"
#include "stmvl53l5_load_fw.h"

#define STMVL53L5_DRV_NAME		"stmvl53l5"
#define STMVL53L5_SLAVE_ADDR		0x29
#define STMVL53L5_MAX_REG_INDEX		0x7fff

#define ST_TOF_IOCTL_TRANSFER	   _IOWR('a',0x1, void*)

struct stmvl53l5_comms_struct {
	__u16   len;
	__u16   reg_index;
	__u8    *buf;
	__u8    write_not_read;
};

static struct miscdevice st_tof_miscdev;
static uint8_t * raw_data_buffer = NULL;

static uint8_t i2c_not_spi = 1;

static uint8_t i2c_driver_added = 0;
static uint8_t spi_driver_registered = 0;
static uint8_t misc_registered = 0;

static struct spi_data_t spi_data;

// ------- i2c ---------------------------
static const struct i2c_device_id stmvl53l5_i2c_id[] = {
	{STMVL53L5_DRV_NAME, 0},
	{},
};

// ------- spi ---------------------------
static const struct spi_device_id stmvl53l5_spi_id[] = {
	{STMVL53L5_DRV_NAME, 0 },
	{ },
};

MODULE_DEVICE_TABLE(i2c, stmvl53l5_i2c_id);

static const struct of_device_id st_tof_of_match[] = {
	{
		/* An older compatible */
		.compatible = "st,stmvl53l5",
		.data = STMVL53L5_DRV_NAME,
	},
	{},
};

MODULE_DEVICE_TABLE(of, st_tof_of_match);  // add to the kernel device tree table

static struct i2c_client *stmvl53l5_i2c_client = NULL;

static struct regulator *p_3v0_vreg = NULL;
static struct regulator *p_1v8_vreg = NULL;

static void disable_power(void);

static int enable_regulator(struct device *dev, const char *supply,
		unsigned int voltage, struct regulator **pp_vreg)
{
	struct regulator *vreg;
	int ret;

	*pp_vreg = NULL;
	vreg = regulator_get(dev, supply);
	if (IS_ERR(vreg)) {
		ret = PTR_ERR(vreg);
		pr_err("stmvl53l5: failed to get %s: %d\n", supply, ret);
		return ret;
	}

	ret = regulator_set_voltage(vreg, voltage, voltage);
	if (ret)
		goto err_put;

	ret = regulator_set_load(vreg, 85000);
	if (ret)
		goto err_reset;

	ret = regulator_enable(vreg);
	if (ret)
		goto err_reset;

	*pp_vreg = vreg;
	return 0;

err_reset:
	regulator_set_load(vreg, 0);
	regulator_set_voltage(vreg, 0, voltage);
err_put:
	regulator_put(vreg);
	return ret;
}

static void disable_regulator(struct regulator **pp_vreg,
		unsigned int voltage)
{
	struct regulator *vreg;

	if (!pp_vreg || !*pp_vreg || IS_ERR(*pp_vreg))
		return;

	vreg = *pp_vreg;
	regulator_disable(vreg);
	regulator_set_load(vreg, 0);
	regulator_set_voltage(vreg, 0, voltage);
	regulator_put(vreg);
	*pp_vreg = NULL;
}

static int enable_regulator_1V8(struct device *dev, struct regulator **pp_vreg)
{
	return enable_regulator(dev, "_1P8_power", 1800000, pp_vreg);
}

static int enable_regulator_3V0(struct device *dev, struct regulator **pp_vreg)
{
	return enable_regulator(dev, "_3P0_power", 3008000, pp_vreg);
}

static int enable_power(struct spi_device *spi)
{
	int ret;

	ret = enable_regulator_3V0(&spi->dev, &p_3v0_vreg);
	if (ret)
		return ret;

	ret = enable_regulator_1V8(&spi->dev, &p_1v8_vreg);
	if (ret) {
		disable_regulator(&p_3v0_vreg, 3008000);
		return ret;
	}

	return 0;
}

static void disable_power(void)
{
	disable_regulator(&p_1v8_vreg, 1800000);
	disable_regulator(&p_3v0_vreg, 3008000);
}

static int stmvl53l5_open(struct inode *inode, struct file *file)
{
	printk("stmvl53l5 : %s(%d)\n", __func__, __LINE__);
	mutex_lock(&spi_data.mutex);
	if (spi_data.removing || (!spi_data.device && !i2c_not_spi) ||
	    (i2c_not_spi && !stmvl53l5_i2c_client)) {
		mutex_unlock(&spi_data.mutex);
		return -ENODEV;
	}
	if (unlikely(spi_data.nusers >= SHRT_MAX)) {
		if (spi_data.device)
			dev_err(&spi_data.device->dev, "device busy\n");
		else
			pr_err("stmvl53l5: device busy\n");
		mutex_unlock(&spi_data.mutex);
		return -EBUSY;
	}
	/*if (spi_data.nusers == 0) {
		regulator_enable(p_3v0_vreg);
		regulator_enable(p_1v8_vreg);
	}*/
	spi_data.nusers++;
	printk("stmvl53l5_open : spi_data.nusers = %u\n", spi_data.nusers);
	mutex_unlock(&spi_data.mutex);

	return 0;
}

static int stmvl53l5_release(struct inode *inode, struct file *file)
{
	printk("stmvl53l5 : %s(%d)\n", __func__, __LINE__);
	mutex_lock(&spi_data.mutex);
	printk("stmvl53l5_release : spi_data.nusers = %u\n", spi_data.nusers);
	if (spi_data.nusers)
		spi_data.nusers--;
	/*if (spi_data.nusers == 0) {
		regulator_disable(p_1v8_vreg);
		regulator_disable(p_3v0_vreg);
	}*/
	mutex_unlock(&spi_data.mutex);

	return 0;
}

static long stmvl53l5_ioctl(struct file *file,
		unsigned int cmd, unsigned long arg)
{
	struct i2c_msg st_i2c_message = {0};
	struct stmvl53l5_comms_struct comms_struct;
	int32_t ret = 0;
	uint16_t index, transfer_size, chunk_size;
	u8 __user *data_ptr;

	if (cmd != ST_TOF_IOCTL_TRANSFER)
		return -ENOTTY;
	if (copy_from_user(&comms_struct, (void __user *)arg,
			   sizeof(comms_struct)))
		return -EFAULT;
	if (!comms_struct.len || comms_struct.write_not_read > 1 ||
	    !comms_struct.buf || comms_struct.reg_index > STMVL53L5_MAX_REG_INDEX ||
	    comms_struct.len > STMVL53L5_MAX_REG_INDEX + 1 -
			comms_struct.reg_index)
		return -EINVAL;

	data_ptr = (u8 __user *)comms_struct.buf;
	if (!access_ok(data_ptr, comms_struct.len))
		return -EFAULT;
	if (mutex_lock_interruptible(&spi_data.mutex))
		return -ERESTARTSYS;
	if (spi_data.removing || !raw_data_buffer ||
	    (i2c_not_spi ? !stmvl53l5_i2c_client : !spi_data.device)) {
		ret = -ENODEV;
		goto out_unlock;
	}
	if (i2c_not_spi && !stmvl53l5_i2c_client) {
		ret = -ENODEV;
		goto out_unlock;
	}

	if (i2c_not_spi) {
		st_i2c_message.addr = STMVL53L5_SLAVE_ADDR;
		st_i2c_message.buf = raw_data_buffer;
	}
	chunk_size = (i2c_not_spi && comms_struct.write_not_read) ?
		VL53L5_COMMS_CHUNK_SIZE - 2 : VL53L5_COMMS_CHUNK_SIZE;

	for (index = 0; index < comms_struct.len; ) {
		transfer_size = min_t(uint16_t, comms_struct.len - index, chunk_size);

		if (comms_struct.write_not_read) {
			if (i2c_not_spi) {
				raw_data_buffer[0] = (comms_struct.reg_index + index) >> 8;
				raw_data_buffer[1] = (comms_struct.reg_index + index) & 0xff;
				if (copy_from_user(&raw_data_buffer[2], data_ptr + index,
						transfer_size)) {
					ret = -EFAULT;
					goto out_unlock;
				}
				st_i2c_message.len = transfer_size + 2;
				st_i2c_message.flags = 0;
				ret = i2c_transfer(stmvl53l5_i2c_client->adapter,
						&st_i2c_message, 1);
				if (ret != 1) {
					ret = -EIO;
					goto out_unlock;
				}
			} else {
				if (copy_from_user(raw_data_buffer, data_ptr + index,
						transfer_size)) {
					ret = -EFAULT;
					goto out_unlock;
				}
				ret = stmvl53l5_spi_write(&spi_data,
						comms_struct.reg_index + index,
						raw_data_buffer, transfer_size);
				if (ret) {
					ret = -EIO;
					goto out_unlock;
				}
			}
		} else {
			if (i2c_not_spi) {
				raw_data_buffer[0] = (comms_struct.reg_index + index) >> 8;
				raw_data_buffer[1] = (comms_struct.reg_index + index) & 0xff;
				st_i2c_message.len = 2;
				st_i2c_message.flags = 0;
				ret = i2c_transfer(stmvl53l5_i2c_client->adapter,
						&st_i2c_message, 1);
				if (ret != 1) {
					ret = -EIO;
					goto out_unlock;
				}
				st_i2c_message.len = transfer_size;
				st_i2c_message.flags = I2C_M_RD;
				ret = i2c_transfer(stmvl53l5_i2c_client->adapter,
						&st_i2c_message, 1);
				if (ret != 1) {
					ret = -EIO;
					goto out_unlock;
				}
			} else {
				ret = stmvl53l5_spi_read(&spi_data,
						comms_struct.reg_index + index,
						raw_data_buffer, transfer_size);
				if (ret) {
					ret = -EIO;
					goto out_unlock;
				}
			}
			if (copy_to_user(data_ptr + index, raw_data_buffer,
					transfer_size)) {
				ret = -EFAULT;
				goto out_unlock;
			}
		}

		index += transfer_size;
	}
	ret = 0;

out_unlock:
	mutex_unlock(&spi_data.mutex);
	return ret;
}

static const struct file_operations stmvl53l5_ranging_fops = {
	.owner 			= THIS_MODULE,
	.unlocked_ioctl		= stmvl53l5_ioctl,
	.open 			= stmvl53l5_open,
	.release 		= stmvl53l5_release,
};

static int stmvl53l5_i2c_probe(struct i2c_client *client,
				const struct i2c_device_id *id)
{
	int ret;
	uint8_t page = 0, revision_id = 0, device_id = 0;

	mutex_lock(&spi_data.mutex);
	if (spi_data.nusers || raw_data_buffer || spi_data.device ||
	    misc_registered ||
	    stmvl53l5_i2c_client) {
		mutex_unlock(&spi_data.mutex);
		return -EBUSY;
	}
	spi_data.device = NULL;
	spi_data.nusers = 0;
	spi_data.removing = true;
	stmvl53l5_i2c_client = client;

	i2c_not_spi = 1;

	printk("stmvl53l5: probing i2c\n");

	raw_data_buffer = kzalloc(VL53L5_COMMS_CHUNK_SIZE, GFP_DMA | GFP_KERNEL);
	if (raw_data_buffer == NULL) {
		ret = -ENOMEM;
		goto fail_state;
	}

	ret = stmvl53l5_write_multi(client, raw_data_buffer, 0x7FFF, &page, 1);
	if (ret)
		goto fail_buffer;
	ret = stmvl53l5_read_multi(client, raw_data_buffer, 0x00, &device_id, 1);
	if (ret)
		goto fail_buffer;
	ret = stmvl53l5_read_multi(client, raw_data_buffer, 0x01, &revision_id, 1);
	if (ret)
		goto fail_buffer;

	if ((device_id != 0xF0) || (revision_id != 0x02)) {
		pr_err("stmvl53l5: Error. Could not read device and revision id registers\n");
		ret = -ENODEV;
		goto fail_buffer;
	}
	printk("stmvl53l5: device_id : 0x%x. revision_id : 0x%x\n", device_id, revision_id);

	ret = stmvl53l5_load_fw_stm(client, raw_data_buffer);
	if (ret) {
		pr_err("stmvl53l5 : Failed in loading the FW into the device, err = %d\n", ret);
		goto fail_buffer;
	}

	ret = stmvl53l5_move_device_to_low_power(client, NULL, 1, raw_data_buffer);
	if (ret) {
		pr_err("stmvl53l5 : could not move the device to low power = %d\n", ret);
		goto fail_buffer;
	}

	st_tof_miscdev.minor = MISC_DYNAMIC_MINOR;
	st_tof_miscdev.name = "stmvl53l5";
	st_tof_miscdev.fops = &stmvl53l5_ranging_fops;
	st_tof_miscdev.mode = 0444;
	ret = misc_register(&st_tof_miscdev);
	if (ret) {
		pr_err("stmvl53l5: failed to register misc device: %d\n", ret);
		goto fail_buffer;
	}
	misc_registered = 1;
	spi_data.removing = false;
	mutex_unlock(&spi_data.mutex);
	return 0;

fail_buffer:
	kfree(raw_data_buffer);
	raw_data_buffer = NULL;
fail_state:
	stmvl53l5_i2c_client = NULL;
	spi_data.device = NULL;
	spi_data.removing = true;
	mutex_unlock(&spi_data.mutex);
	return ret;
}

static int stmvl53l5_i2c_remove(struct i2c_client *client)
{
	mutex_lock(&spi_data.mutex);
	spi_data.removing = true;
	kfree(raw_data_buffer);
	raw_data_buffer = NULL;
	spi_data.device = NULL;
	stmvl53l5_i2c_client = NULL;
	mutex_unlock(&spi_data.mutex);

	if (misc_registered) {
		misc_deregister(&st_tof_miscdev);
		misc_registered = 0;
	}
	return 0;
}

static struct i2c_driver stmvl53l5_i2c_driver = {
	.driver = {
		.name = STMVL53L5_DRV_NAME,
		.owner = THIS_MODULE,
		.of_match_table = of_match_ptr(st_tof_of_match), // for platform register to pick up the dts info
	},
	.probe = stmvl53l5_i2c_probe,
	.remove = stmvl53l5_i2c_remove,
	.id_table = stmvl53l5_i2c_id,
};

static int stmvl53l5_spi_probe(struct spi_device *spi)
{
	int ret;
	uint8_t page = 0, revision_id = 0, device_id = 0;

	mutex_lock(&spi_data.mutex);
	if (spi_data.nusers || raw_data_buffer || spi_data.device ||
	    misc_registered ||
	    stmvl53l5_i2c_client) {
		mutex_unlock(&spi_data.mutex);
		return -EBUSY;
	}
	spi_data.nusers = 0;
	spi_data.removing = true;
	spi_data.device = spi;
	mutex_unlock(&spi_data.mutex);

	ret = enable_power(spi);
	if (ret) {
		pr_err("stmvl53l5: failed to enable power: %d\n", ret);
		goto fail_state;
	}

	i2c_not_spi = 0;
	spi_data.device->mode |= SPI_CPHA;
	spi_data.device->mode |= SPI_CPOL;
	ret = spi_setup(spi);
	if (ret) {
		pr_err("stmvl53l5: spi_setup failed: %d\n", ret);
		goto fail_power;
	}

	ret = stmvl53l5_spi_write(&spi_data, 0x7FFF, &page, 1);
	if (ret)
		goto fail_power;
	ret = stmvl53l5_spi_read(&spi_data, 0x00, &device_id, 1);
	if (ret)
		goto fail_power;
	ret = stmvl53l5_spi_read(&spi_data, 0x01, &revision_id, 1);
	if (ret)
		goto fail_power;

	if ((device_id != 0xF0) || (revision_id != 0x02)) {
		pr_err("stmvl53l5: unexpected device/revision: 0x%x/0x%x\n",
			device_id, revision_id);
		ret = -ENODEV;
		goto fail_power;
	}
	printk("stmvl53l5: device_id : 0x%x. revision_id : 0x%x\n", device_id, revision_id);

	raw_data_buffer = kzalloc(VL53L5_COMMS_CHUNK_SIZE, GFP_DMA | GFP_KERNEL);
	if (raw_data_buffer == NULL) {
		ret = -ENOMEM;
		goto fail_power;
	}
	st_tof_miscdev.minor = MISC_DYNAMIC_MINOR;
	st_tof_miscdev.name = "stmvl53l5";
	st_tof_miscdev.fops = &stmvl53l5_ranging_fops;
	st_tof_miscdev.mode = 0444;

	ret = misc_register(&st_tof_miscdev);
	if (ret) {
		pr_err("stmvl53l5 : Failed to create misc device, err = %d\n", ret);
		goto fail_buffer;
	}

	mutex_lock(&spi_data.mutex);
	misc_registered = 1;
	spi_data.removing = false;
	mutex_unlock(&spi_data.mutex);
	return 0;

fail_buffer:
	kfree(raw_data_buffer);
	raw_data_buffer = NULL;
fail_power:
	disable_power();
fail_state:
	spi_data.device = NULL;
	spi_data.removing = true;
	return ret;

}

static int stmvl53l5_spi_remove(struct spi_device *device)
{
	bool deregister = false;

	mutex_lock(&spi_data.mutex);
	spi_data.removing = true;
	deregister = misc_registered;
	misc_registered = 0;
	kfree(raw_data_buffer);
	raw_data_buffer = NULL;
	spi_data.device = NULL;
	disable_power();
	mutex_unlock(&spi_data.mutex);

	if (deregister)
		misc_deregister(&st_tof_miscdev);

	return 0;
}

static struct spi_driver stmvl53l5_spi_driver = {
	.driver = {
		.name   = STMVL53L5_DRV_NAME,
		.owner  = THIS_MODULE,
	},
	.probe  = stmvl53l5_spi_probe,
	.remove = stmvl53l5_spi_remove,
	.id_table = stmvl53l5_spi_id,
};

static int __init st_tof_module_init(void)
{
	int ret = 0;

	printk("stmvl53l5: module init\n");
	mutex_init(&spi_data.mutex);
	spi_data.nusers = 0;
	spi_data.device = NULL;
	spi_data.removing = false;

	/* register as a i2c client device */
/*	ret = i2c_add_driver(&stmvl53l5_i2c_driver);

	if (ret) {
		i2c_del_driver(&stmvl53l5_i2c_driver);
		printk("stmvl53l5: could not add i2c driver\n");
		return ret;
	}

	i2c_driver_added = 1;
*/
	ret = spi_register_driver(&stmvl53l5_spi_driver);
	if (ret) {
		printk("stmvl53l5: could not register spi driver : %d", ret);
		return ret;
	}

	spi_driver_registered = 1;

	return ret;
}

static void __exit st_tof_module_exit(void)
{

	printk("stmvl53l5 : module exit\n");

	if (misc_registered) {
		misc_deregister(&st_tof_miscdev);
		misc_registered = 0;
	}

	if (spi_driver_registered) {
		spi_unregister_driver(&stmvl53l5_spi_driver);
		spi_driver_registered = 0;
	}

	if (i2c_driver_added) {
		i2c_del_driver(&stmvl53l5_i2c_driver);
		i2c_driver_added = 0;
	}

}

module_init(st_tof_module_init);
module_exit(st_tof_module_exit);
MODULE_LICENSE("GPL");





