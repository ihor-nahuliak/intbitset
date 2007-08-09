# $Id$

## This file is part of CDS Invenio.
## Copyright (C) 2002, 2003, 2004, 2005, 2006, 2007 CERN.
##
## CDS Invenio is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation; either version 2 of the
## License, or (at your option) any later version.
##
## CDS Invenio is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with CDS Invenio; if not, write to the Free Software Foundation, Inc.,
## 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

"""
Defines an intbitset data object to hold unordered sets of unsigned
integers with ultra fast set operations, implemented via bit vectors
and Python C extension to optimize speed and memory usage.

Emulates the Python built-in set class interface with some additional
specific methods such as its own fast dump and load marshalling
functions.  Uses real bits to optimize memory usage, so may have
issues with endianness if you transport serialized bitsets between
various machine architectures.
"""

import zlib
from array import array

ctypedef unsigned long long int word_t
ctypedef unsigned int size_t
ctypedef unsigned long int Py_ssize_t
ctypedef unsigned char bool_t

cdef extern from "Python.h":
    object PyString_FromStringAndSize(char *s, int len)
    int PyObject_AsReadBuffer(object obj, void **buf, int *buf_len)

cdef extern from "intbitset.h":
    ctypedef struct IntBitSet:
        int size
        size_t allocated
        word_t universe
        int tot
        word_t *bitset
    size_t wordbytesize
    size_t wordbitsize
    IntBitSet *intBitSetCreate(size_t size, bool_t universe)
    IntBitSet *intBitSetCreateFromBuffer(void *buf, size_t bufsize)
    IntBitSet *intBitSetResetFromBuffer(IntBitSet *bitset, void *buf, size_t bufsize)
    IntBitSet *intBitSetReset(IntBitSet *bitset)
    void intBitSetDestroy(IntBitSet *bitset)
    IntBitSet *intBitSetClone(IntBitSet *bitset)
    int intBitSetGetSize(IntBitSet *bitset)
    int intBitSetGetAllocated(IntBitSet *bitset)
    size_t intBitSetGetTot(IntBitSet * bitset)
    bool_t intBitSetIsInElem(IntBitSet *bitset, size_t elem)
    void intBitSetAddElem(IntBitSet *bitset, size_t elem)
    void intBitSetDelElem(IntBitSet *bitset, size_t elem)
    bool_t intBitSetEmpty(IntBitSet *bitset)
    IntBitSet *intBitSetUnion(IntBitSet *x, IntBitSet *y)
    IntBitSet *intBitSetIntersection(IntBitSet *x, IntBitSet *y)
    IntBitSet *intBitSetSub(IntBitSet *x, IntBitSet *y)
    IntBitSet *intBitSetXor(IntBitSet *x, IntBitSet *y)
    IntBitSet *intBitSetIUnion(IntBitSet *dst, IntBitSet *src)
    IntBitSet *intBitSetIIntersection(IntBitSet *dst, IntBitSet *src)
    IntBitSet *intBitSetISub(IntBitSet *x, IntBitSet *y)
    IntBitSet *intBitSetIXor(IntBitSet *x, IntBitSet *y)
    int intBitSetGetNext(IntBitSet *x, int last)
    unsigned char intBitSetCmp(IntBitSet *x, IntBitSet *y)

cdef class intbitset:
    """
    Defines an intbitset data object to hold unordered sets of
    unsigned integers with ultra fast set operations, implemented via
    bit vectors and Python C extension to optimize speed and memory
    usage.

    Emulates the Python built-in set class interface with some
    additional specific methods such as its own fast dump and load
    marshalling functions.  Uses real bits to optimize memory usage,
    so may have issues with endianness if you transport serialized
    bitsets between various machine architectures.
    """
    cdef IntBitSet *bitset

    def __new__(self, rhs=0, int minsize=-1, universe=0):
        """Initialize intbitset. rhs can be:
        int/long for creating allocating empty intbitset that will hold at least
            rhs elements, before being resized
        intbitset for cloning
        str for retrieving an intbitset that was dumped into a string
        array for retrieving an intbitset that was dumpeg into a string stored
            in an array
        a sequence made of integers for copying all the elements from the
            sequence. If minsize is specified than it is initially allocated
            enough space to hold up to minsize integers, otherwise the biggest
            element of the sequence will be used.
        """
        cdef int size
        cdef void *buf
        cdef size_t elem
        cdef char *msg
        cdef size_t i
        cdef size_t last
        cdef size_t remelem
        msg = "Error"
        self.bitset = NULL
        buf = NULL
        size = 0
        elem = 0
        i = 0
        last = 0
        remelem = 0
        if type(rhs) in (int, long):
            if rhs < 0:
                raise ValueError, "rhs can't be negative"
            self.bitset = intBitSetCreate(rhs, universe)
        elif type(rhs) is intbitset:
            self.bitset = intBitSetClone((<intbitset>rhs).bitset)
        elif type(rhs) in (str, array):
            try:
                if type(rhs) is array:
                    rhs = rhs.tostring()
                tmp = zlib.decompress(rhs)
                if PyObject_AsReadBuffer(tmp, &buf, &size) < 0:
                    raise Exception, "Buffer error!!!"
                self.bitset = intBitSetCreateFromBuffer(buf, size)
            except Exception, msg:
                raise ValueError, "rhs is corrupted: %s" % msg
        elif hasattr(rhs, '__iter__'):
            try:
                if minsize > -1:
                    self.bitset = intBitSetCreate(minsize, universe)
                else:
                    if rhs:
                        self.bitset = intBitSetCreate(int(max(rhs)), universe)
                    else:
                        self.bitset = intBitSetCreate(0, universe)
                if universe:
                    last = 0
                    for elem in rhs:
                        for remelem from last <= remelem < elem:
                            intBitSetDelElem(self.bitset, remelem)
                        last = elem + 1
                else:
                    for elem in rhs:
                        intBitSetAddElem(self.bitset, elem)
            except Exception, msg:
                raise ValueError, "retrieving integers from rhs is impossible: %s" \
                    % msg
        else:
            raise TypeError, "rhs is of unknown type %s" % type(rhs)

    def __dealloc__(self):
        if self.bitset:
            intBitSetDestroy(self.bitset)

    def __contains__(self, unsigned int elem):
        return intBitSetIsInElem(self.bitset, elem) != 0

    def __cmp__(self, intbitset rhs not None):
        raise TypeError, "cannot compare intbitset using cmp()"

    def __richcmp__(self, intbitset rhs not None, int op):
        cdef short unsigned int tmp
        tmp = intBitSetCmp((<intbitset>self).bitset, rhs.bitset)
        if op == 0: # <
            return tmp == 1
        if op == 1: # <=
            return tmp <= 1
        if op == 2: # ==
            return tmp == 0
        if op == 3: # !=
            return tmp > 0
        if op == 4: # >
            return tmp == 2
        if op == 5: # >=
            return tmp in (0, 2)

    def __len__(self):
        return intBitSetGetTot(self.bitset)

    def __hash__(self):
        return hash(PyString_FromStringAndSize(<char *>self.bitset.bitset, wordbytesize * (intBitSetGetTot(self.bitset) / wordbitsize + 1)))

    def __nonzero__(self):
        return not intBitSetEmpty(self.bitset)

    def __iadd__(self, rhs):
        cdef size_t elem
        if isinstance(rhs, (int, long)):
            intBitSetAddElem(self.bitset, rhs)
        elif isinstance(rhs, intbitset):
            intBitSetIUnion(self.bitset, (<intbitset> rhs).bitset)
        else:
            for elem in rhs:
                intBitSetAddElem(self.bitset, elem)
        return self

    def __isub__(self, rhs):
        cdef size_t elem
        if isinstance(rhs, (int, long)):
            intBitSetDelElem(self.bitset, rhs)
        elif isinstance(rhs, intbitset):
            intBitSetISub(self.bitset, (<intbitset> rhs).bitset)
        else:
            for elem in rhs:
                intBitSetDelElem(self.bitset, elem)
        return self

    def __deepcopy__(self, memo):
        return intbitset(self)

    def __del__(self, size_t elem):
        intBitSetDelElem(self.bitset, elem)

    def __and__(self, intbitset rhs not None):
        ret = intbitset()
        intBitSetDestroy((<intbitset>ret).bitset)
        (<intbitset>ret).bitset = intBitSetIntersection((<intbitset> self).bitset, rhs.bitset)
        return ret

    def __or__(self, intbitset rhs not None):
        ret = intbitset()
        intBitSetDestroy((<intbitset>ret).bitset)
        (<intbitset>ret).bitset = intBitSetUnion((<intbitset> self).bitset, rhs.bitset)
        return ret

    def __xor__(self, intbitset rhs not None):
        ret = intbitset()
        intBitSetDestroy((<intbitset>ret).bitset)
        (<intbitset>ret).bitset = intBitSetXor((<intbitset> self).bitset, rhs.bitset)
        return ret

    def __sub__(self, intbitset rhs not None):
        ret = intbitset()
        intBitSetDestroy((<intbitset>ret).bitset)
        (<intbitset>ret).bitset = intBitSetSub((<intbitset> self).bitset, rhs.bitset)
        return ret

    def __iand__(self, intbitset rhs not None):
        intBitSetIIntersection(self.bitset, rhs.bitset)
        return self

    def __ior__(self, intbitset rhs not None):
        intBitSetIUnion(self.bitset, rhs.bitset)
        return self

    def __ixor__(self, intbitset rhs not None):
        intBitSetIXor(self.bitset, rhs.bitset)
        return self

    def __repr__(self):
        cdef int last
        cdef int maxelem
        if self.bitset.universe:
            maxelem = (intBitSetGetSize(self.bitset)) * wordbitsize
            ret = "intbitset(["
            last = -1
            while last < maxelem:
                last = intBitSetGetNext(self.bitset, last)
                ret = ret + '%i, ' % last
            if ret.endswith(", "):
                ret = ret[:-2]
            ret = ret + '], universe=True)'
            return ret
        else:
            ret = "intbitset(["
            last = -1
            while last >= -1:
                last = intBitSetGetNext(self.bitset, last)
                ret = ret + '%i, ' % last
            ret = ret[:-len('-2, ')]
            if ret.endswith(', '):
                ret = ret[:-2]
            ret = ret + '])'
            return ret

    def __str__(self):
        cdef int tot
        tot = intBitSetGetTot(self.bitset)
        if tot < 0:
            begin_list = self.to_sorted_list(0, 10)
            ret = "intbitset(["
            for n in begin_list:
                ret = ret + '%i, ' % n
            ret = ret + "...])"
            return ret
        elif tot > 10:
            begin_list = self.to_sorted_list(0, 5)
            end_list = self.to_sorted_list(tot - 5, tot)
            ret = "intbitset(["
            for n in begin_list:
                ret = ret + '%i, ' % n
            ret = ret + "..., "
            for n in end_list:
                ret = ret + '%i, ' % n
            ret = ret[:-2]
            ret = ret + '])'
            return ret
        else:
            return self.__repr__()

    ## Buffer interface
    #def __getreadbuffer__(self, int i, void **p):
        #if i != 0:
            #return -1
        #p[0] = (<intbitset >self).bitset
        #return (<intbitset >self).size * wordbytesize

    #def __getwritebuffer__(self, int i, void **p):
        #if i != 0:
            #raise SystemError
        #p[0] = (<intbitset >self).bitset
        #return (<intbitset >self).size * wordbytesize

    #def __getsegcount__(self, int *p):
        #if p != NULL:
            #p[0] = (<intbitset >self).size * wordbytesize
        #return 1

    #def __getcharbuffer__(self, int i, char **p):
        #if i != 0:
            #return -1
        #p[0] = <char *> (<intbitset >self).bitset
        #return (<intbitset >self).size * wordbytesize

    # Iterator interface
    def __iter__(self):
        return intbitset_iterator(self)

    # Customized interface
    def add(self, size_t elem):
        """Add an element to a set.
        This has no effect if the element is already present."""
        intBitSetAddElem(self.bitset, elem)

    def clear(self):
        intBitSetReset(self.bitset)

    def difference(intbitset self, intbitset rhs):
        """Return the difference of two intbitsets as a new set.
        (i.e. all elements that are in this intbitset but not the other.)
        """
        return self.__sub__(rhs)

    def difference_update(self, intbitset rhs):
        """Remove all elements of another set from this set."""
        self.__isub__(rhs)

    def discard(self, size_t elem):
        """Remove an element from a intbitset if it is a member.
        If the element is not a member, do nothing."""
        intBitSetDelElem(self.bitset, elem)

    def intersection(self, intbitset rhs):
        """Return the intersection of two intbitsets as a new set.
        (i.e. all elements that are in both intbitsets.)
        """
        return self.__and__(rhs)

    def intersection_update(self, intbitset rhs):
        """Update a intbitset with the intersection of itself and another."""
        self.__iand__(rhs)

    def union(self, intbitset rhs):
        """Return the union of two intbitsets as a new set.
        (i.e. all elements that are in either intbitsets.)
        """
        return self.__or__(rhs)

    def union_update(self, intbitset rhs):
        """Update a intbitset with the union of itself and another."""
        self.__ior__(rhs)

    def issubset(self, intbitset rhs):
        """Report whether another set contains this set."""
        return self.__le__(rhs)

    def issuperset(self, intbitset rhs):
        """Report whether this set contains another set."""
        return self.__ge__(rhs)

    def symmetric_difference(self, intbitset rhs):
        """Return the symmetric difference of two sets as a new set.
        (i.e. all elements that are in exactly one of the sets.)
        """
        return self.__xor__(rhs)

    def symmetric_difference_update(self, intbitset rhs):
        """Update an intbitset with the symmetric difference of itself and another.
        """
        self.__ixor__(rhs)

    # Dumping & Loading
    def fastdump(self):
        """Return a compressed string representation suitable to be saved
        somewhere."""
        cdef int size
        size = intBitSetGetSize((<intbitset> self).bitset)
        assert(size < self.bitset.allocated)
        return zlib.compress(PyString_FromStringAndSize(<char *>self.bitset.bitset, ( size + 1) * wordbytesize))

    def fastload(self, strdump):
        """Load a compressed string representation produced by a previous call
        to the fastdump method into the current intbitset. The previous content
        will be replaced."""
        cdef int size
        cdef void *buf
        try:
            if type(strdump) is array:
                strdump = strdump.tostring()
            PyObject_AsReadBuffer(zlib.decompress(strdump), &buf, &size)
            intBitSetResetFromBuffer((<intbitset> self).bitset, buf, size)
        except:
            raise ValueError, "strdump is corrupted"
        return self

    def copy(self):
        """Return a shallow copy of a set."""
        return intbitset(self)

    def pop(self):
        """Remove and return an arbitrary set element."""
        cdef int ret
        ret = intBitSetGetNext(self.bitset, -1)
        if ret < 0:
            raise KeyError, "pop from an empty intbitset"
        intBitSetDelElem(self.bitset, ret)
        return ret

    def remove(self, size_t elem):
        """Remove an element from a set; it must be a member.
        If the element is not a member, raise a KeyError.
        """
        if intBitSetIsInElem(self.bitset, elem):
            intBitSetDelElem(self.bitset, elem)
        else:
            raise KeyError, elem

    def strbits(self):
        """Return a string of 0s and 1s representing the content in memory
        of the intbitset.
        """
        cdef size_t i
        cdef size_t last
        if (<intbitset> self).bitset.universe:
            raise OverflowError, "It's impossible to print universe."
        last = 0
        ret = ''
        for i in self:
            ret = ret + '0'*(i-last)+'1'
            last = i+1
        return ret

    def update_with_signs(self, rhs):
        """Given a dictionary rhs whose keys are integers, remove all the integers
        whose value are less than 0 and add every integer whose value is 0 or more"""
        cdef size_t value
        try:
            for value, sign in rhs.items():
                if sign < 0:
                    intBitSetDelElem(self.bitset, value)
                else:
                    intBitSetAddElem(self.bitset, value)
        except AttributeError:
            raise TypeError, "rhs should be a valid dictionary with integers keys and integer values"

    def get_size(self):
        return intBitSetGetSize(self.bitset)

    def get_allocated(self):
        return intBitSetGetAllocated(self.bitset)


    def get_sorted_element(self, int index):
        """Return element at position index in the sorted representation of the
        set. Note that index must be less than len(self)"""
        cdef size_t l
        cdef int last
        cdef size_t i
        l = intBitSetGetTot(self.bitset)
        if index < 0:
            index = index + l
        if 0 <= index < l:
            last = intBitSetGetNext(self.bitset, -1)
            for i from 0 <= i < index:
                last = intBitSetGetNext(self.bitset, last)
        else:
            raise IndexError, "intbitset index out of range"
        return last

    def to_sorted_list(self, int i, int j):
        """Return a sublist of the sorted representation of the set.
        Note, negative indices are not supported."""
        cdef size_t l
        cdef int last
        cdef size_t cnt
        l = intBitSetGetTot(self.bitset)
        if i == 0 and j == -1:
            return intbitset(self)
        ret = intbitset()
        if i < 0:
            i = i + l
        if j < 0:
            j = j + l
        if i >= l:
            i = l
        if j >= l:
            j = l
        last = -1
        for cnt from 0 <= cnt < i:
            last = intBitSetGetNext(self.bitset, last)
        for cnt from i <= cnt < j:
            last = intBitSetGetNext(self.bitset, last)
            intBitSetAddElem((<intbitset> ret).bitset, last)
        return ret

cdef class intbitset_iterator:
    cdef int last
    cdef IntBitSet *bitset

    def __new__(self, intbitset bitset not None):
        self.last = -1
        self.bitset = bitset.bitset

    def __next__(self):
        self.last = intBitSetGetNext((<intbitset_iterator>self).bitset, self.last)
        if self.last < 0:
            self.last = -2
            raise StopIteration
        return self.last

    def __iter__(self):
        return self
