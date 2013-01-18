import sys
import traceback


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
    arg parameter and calls its trigger method. Note that in the case of signals,
    fd is the signal constant, rather than the file descriptor.
    """
    (<Event>arg).trigger(fd, ev)


cdef timeval ms_timeval(unsigned int ms) with gil:
    """Creates a tv struct representing the specified number of milliseconds.
    """
    cdef timeval tv

    if ms is not None:
        sec, rem = divmod(ms, 1000)
        usec = rem * 1000
        print 'Seconds:', sec, 'Microseconds:', usec

        tv.tv_sec = sec
        tv.tv_usec = usec

    return tv


cdef class Loop(object):
    """Wraps the event_base struct and provides convenience methods on top of
    it. Additionally provides methods to create and manage events.
    """
    cdef event_base* base
    cdef object registry
    cdef object on_error

    def __init__(self, on_error=None):
        self.base = event_base_new()
        self.registry = {}
        self.on_error = on_error

    def __del__(self):
        if self.base != NULL:
            event_base_free(self.base)
            self.base = NULL

    def run(self):
        """Starts the event loop.
        """
        with nogil:
            event_base_dispatch(self.base)

    def exit(self):
        """Halts the event loop.
        """
        event_base_loopbreak(self.base)

    def abort(self):
        for event in self.registry.values():
            self.cancel(event)
        event_base_loopbreak(self.base)

    cdef Event add_event(self, Event event):
        self.registry[event] = event
        event.set_loop(self)
        event.enable()
        return event

    def watch(self, *args, **kwargs):
        """Creates and returns a new Event object. Events are persistent by
        default. The specified file handle may be a file-like object or a raw
        file descriptor (int).
        """
        return self.add_event(Event(*args, **kwargs))

    def set_timer(self, after, callback):
        return self.add_event(Timer(after, callback))

    def set_interval(self, every, callback):
        return self.add_event(Interval(every, callback))

    def set_alarm(self, signal, callback):
        return self.add_event(Signal(signal, callback))

    def cancel(self, event):
        """Disables an event.
        """
        event.disable()
        del self.registry[event]

    def _callback(self, event, callback, *args, **kwargs):
        try:
            callback(event, *args, **kwargs)
        except Exception, e:
            if self.on_error is not None:
                self.on_error(e, self, event, args, kwargs)
            else:
                (tp, val, tb) = sys.exc_info()
                sys.stderr.write('An exception occurred within an event callback.\n')
                traceback.print_exc(tb)
                self.abort()


cdef class Event(object):
    """Events are observers that trigger callbacks when a file handle signals
    readiness to read/write, when a signal is received, or when a timer or
    interval is scheduled. This class should not be manually instantiated by
    the caller; use Loop.watch() instead.
    """
    cdef Loop loop
    cdef event* event
    cdef timeval tv
    cdef short int mask
    cdef object callback
    cdef object handle

    def __init__(self, handle, mask, callback, timeout=None, persistent=True):
        if persistent:
            mask = mask | EV_PERSIST

        self.handle = handle
        self.mask = mask
        self.callback = callback

        if timeout is not None:
            self.tv = ms_timeval(timeout)

    def __del__(self):
        event_free(self.event)

    cdef set_loop(self, Loop loop):
        self.loop = loop

    @property
    def fd(self):
        """Returns the file descriptor of the configured handle.
        """
        if self.handle is None or self.handle == 0:
            return 0
        elif isinstance(self.handle, int):
            return self.handle
        else:
            return self.handle.fileno()

    def enable(self):
        """Enables the event.
        """
        if self.loop is None:
            raise AttributeError('event loop has not yet been set')

        if self.event == NULL:
            self.event = event_new(self.loop.base, self.fd, self.mask, <event_callback_fn>_callback, <void*>self)

        if self.tv.tv_usec:
            event_add(self.event, &self.tv)
        else:
            event_add(self.event, NULL)

        Py_INCREF(self)

    def disable(self):
        """Disables the event.
        """
        event_del(self.event)
        Py_DECREF(self)

    cdef trigger(self, fd, mask):
        self.loop._callback(self, self.callback, self.handle, mask)


cdef class Timer(Event):
    def __init__(self, after, callback):
        Event.__init__(self, 0, EV_TIMEOUT, callback, timeout=after, persistent=False)

    cdef trigger(self, fd, mask):
        self.loop._callback(self, self.callback, mask)


cdef class Interval(Event):
    def __init__(self, every, callback):
        Event.__init__(self, 0, EV_TIMEOUT, callback, timeout=every, persistent=True)

    cdef trigger(self, fd, mask):
        self.loop._callback(self, self.callback, mask)


cdef class Signal(Event):
    def __init__(self, signal, callback):
        Event.__init__(self, signal, EV_SIGNAL, callback, persistent=True)

    cdef trigger(self, signal, mask):
        self.loop._callback(self, self.callback, signal, mask)
