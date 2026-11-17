# The public half of the key that release builds are signed with. The updater
# only installs a download whose signature checks out against this.
#
# Made by tools/make_update_key.sh. The private half is the UPDATE_SIGNING_KEY
# secret on GitHub (and wherever its owner keeps a copy), never this repository.
extends RefCounted

const PEM := """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAzkYcIVshCl0PEtVcwru1
YXAVKp+eXmH5NCTrKhFAZg66fOq1W753PYnsOdrwIrHF2x4cRWe8EyuQt9vTbBJn
mAZLGjpsmiVtyBJgXPTe7i3NFzyJ86/zYzB4vGLAYX/73zw7Ee+T+BFcywxZJIDS
ddFHJ/KnWX6QWV0IxMc1+p7uA64JW6UMqEqQd0fPv3rY4rha5Ksc56E4XFEe4Pgp
xO+4Sj//ZFD0CxL+Fu6ZwS/v210+4RZhSttJMPWJ8TwgZM6SxVERpfi1+eGg/PIO
tlRKoBAD9xnOO1SanUMxAL0yVK9a0WCn5QiJXDTaMKtVlUg3cbzR8PTduYBJB/nh
MqJ3+kIkG+rXqx7mLZqeAhAh41oXvK40bitWdOlH5TQXK+agXluVvrbG47fxbGVD
BzND6t0lNMtYlaQ3f2v9YPyQAZ8WjbgjsREkrgRFgUc4JxHfpKmaBkhqW32wCgos
xR5dfWuVWShJrszM5fh3SlGEVNatp2kOSiox9erkosPvAgMBAAE=
-----END PUBLIC KEY-----
"""
