from distutils.core import setup
from distutils.extension import Extension


use_cython = True
try:
    from Cython.Distutils import build_ext
except ImportError, e:
    print e
    use_cython = False


cmdclass = {}
ext_modules = []

if use_cython:
    ext_modules.append(Extension("coal.libevent", ["cython/libevent.pyx"]))
    cmdclass['build_ext'] = build_ext
else:
    ext_modules.append(Extension("coal.libevent", ["cython/libevent.c"]))


setup(
    name='coal',
    description=('An event-based framework based on libevent2.'),
    version='0.1',
    author='Jeff Ober',
    author_email='jeffober@gmail.com',
    url='',

    packages=['coal', 'coal.libevent'],
    cmdclass = cmdclass,
    ext_modules = ext_modules,
)

