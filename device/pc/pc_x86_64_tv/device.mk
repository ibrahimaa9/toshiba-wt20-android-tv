#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# ATV
PRODUCT_IS_ATV := true

# Inherit from device
$(call inherit-product, device/pc/pc_x86_64/device.mk)

# Characteristics
PRODUCT_CHARACTERISTICS := tv
