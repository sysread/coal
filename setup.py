from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext

setup(
    name='coal',
    description=('An event-based framework based on libevent2.'),
    version='0.1',
    author='Jeff Ober',
    author_email='jeffober@gmail.com',
    url='',

    cmdclass = {'build_ext': build_ext},
    ext_modules = [
        Extension("libevent", ["libevent.pyx"], libraries=['event']),
    ]
)
