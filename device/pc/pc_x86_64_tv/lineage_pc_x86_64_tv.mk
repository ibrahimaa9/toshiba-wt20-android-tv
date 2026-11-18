#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Toshiba WT20 on a TV: Android TV with Google TV's home screen and services (apply22a).
# Read before the inherited makefiles below (virt-common and options.mk test them).
PRODUCT_IS_ATV := true
WT20_ATV := true
include device/pc/wt20/options.mk

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, device/google/atv/products/atv_base.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_tv.mk)

# Inherit from device
$(call inherit-product, device/pc/pc_x86_64_tv/device.mk)

# Toshiba WT20 additions (hardware, remote access, zram, TV display handling)
$(call inherit-product, device/pc/wt20/wt20.mk)

PRODUCT_NAME := lineage_pc_x86_64_tv
PRODUCT_DEVICE := pc_x86_64_tv
PRODUCT_BRAND := PC
PRODUCT_MANUFACTURER := PC
PRODUCT_MODEL := PC x86_64 TV

PRODUCT_VENDOR_PROPERTIES += \
    ro.soc.manufacturer=$(PRODUCT_MANUFACTURER) \
    ro.soc.model=$(PRODUCT_DEVICE)

# Google TV apps and services (from Google's Android 16 Google TV emulator image)
$(call inherit-product, vendor/gapps_tv/gapps.mk)
