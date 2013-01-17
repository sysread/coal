EV_TIMEOUT = 0x01
EV_READ    = 0x02
EV_WRITE   = 0x04
EV_SIGNAL  = 0x08
EV_PERSIST = 0x10

# Event callback type
ctypedef void (*event_callback_fn)(int fd, short event, void *arg)


# Python macros to increment/decrement refcounts
cdef extern from "Python.h":
    void Py_INCREF(object o)
    void Py_DECREF(object o)


# Import libevent defs
cdef extern from "event2/event.h":
    struct timeval:
        unsigned int tv_sec
        unsigned int tv_usec

    struct event_base:
        pass

    struct event:
        pass

    event_base* event_base_new()
    void event_base_free(event_base *base)
    int event_base_dispatch(event_base *base) nogil
    int event_base_loopbreak(event_base *base)

    event* event_new(event_base *base, int fd, short event, event_callback_fn handler, void *arg)
    void event_free(event *ev)
    int event_add(event *ev, timeval *timeout)
    int event_del(event *ev)


cdef void _callback(int fd, short ev, void* arg) with gil:
    """Generic callback passed to event_new. Uses the Event class instance as the
    arg parameter and calls its trigger method.
    """
    (<Event>arg).trigger(fd, ev)


cdef timeval ms_timeval(unsigned int ms) with gil:
    """Creates a tv struct representing the specified number of milliseconds.
    """
    cdef timeval tv

    if ms is not None:
        us = ms * 1000
        if us < ms: # int wrapped
            raise ValueError('Parameter <ms> expects a positive integer value not greater than MAX_INT/1000')

        tv.sec = 0
        tv.usec = ms * 1000

    return tv


cdef class Loop(object):
    cdef event_base* base

    def __init__(self):
        self.base = event_base_new()

    def __del__(self):
        if self.base != NULL:
            event_base_free(self.base)
            self.base = NULL

    def run(self):
        with nogil:
            event_base_dispatch(self.base)

    def exit(self):
        event_base_loopbreak(self.base)

    def watch(self, handle, mask, callback, timeout=None, persistent=True):
        if persistent:
            mask = mask | EV_PERSIST
        event = Event(handle, mask, callback)
        event.set_base(self.base)
        event.enable(timeout)

    def cancel(self, event):
        event.disable()


cdef class Event(object):
    cdef event_base* base
    cdef event* event
    cdef timeval tv
    cdef short int mask
    cdef object callback
    cdef object handle

    def __init__(self, handle, mask, callback):
        self.handle = handle
        self.mask = mask
        self.callback = callback

    def __del__(self):
        event_free(self.event)

    cdef set_base(self, event_base* base):
        self.base = base

    @property
    def fd(self):
        if isinstance(self.handle, int):
            return self.handle
        else:
            return self.handle.fileno()

    def enable(self, timeout=None):
        if self.base == NULL:
            raise AttributeError('event base has not yet been set')

        if self.event == NULL:
            self.event = event_new(self.base, self.fd, self.mask, _callback, <void*>self)

        if timeout is not None:
            self.tv = ms_timeval(timeout)

        if self.tv.tv_usec:
            event_add(self.event, &self.tv)
        else:
            event_add(self.event, NULL)

        Py_INCREF(self)

    def disable(self):
        event_del(self.event)
        Py_DECREF(self)

    def trigger(self, fd, evmask):
        self.callback(self, fd, evmask)


cdef class Timer(Event):
    pass


cdef class Interval(Event):
    pass


cdef class Signal(Event):
    pass

