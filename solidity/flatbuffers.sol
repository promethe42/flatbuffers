pragma solidity ^0.4.0;

library Table {
  struct Table {
    bytes bb;
    uint32 bb_pos;
  }
}

library Builder {
  using ByteBuffer for ByteBuffer.ByteBuffer;

  struct Builder {
    ByteBuffer.ByteBuffer bb;
    uint32 space;
    uint32 minalign;
    uint32 vtable_in_use;
    bool isNested;
    uint32 object_start;
    uint32[] vtable;
    uint32[] vtables;
    uint32 vector_num_elems;
    bool force_defaults;
  }

  function create(uint32 opt_initial_size) internal returns (Builder) {
    var initial_size = opt_initial_size;
    if (opt_initial_size == 0) {
      initial_size = 2014;
    }

    Builder memory builder;

    builder.bb.data = new bytes(initial_size);
    builder.space = initial_size;
    builder.minalign = 1;
    builder.vtable_in_use = 0;
    builder.isNested = false;
    builder.object_start = 0;
    builder.vector_num_elems = 0;
    builder.force_defaults = false;

    return builder;
  }

  function growByteBuffer(ByteBuffer.ByteBuffer storage bb) internal {
    var old_buf_size = bb.capacity();

    // Ensure we don't grow beyond what fits in an int.
    if (old_buf_size & 0xC0000000 != 0) {
      throw; // FlatBuffers: cannot grow buffer beyond 2 gigabytes.
    }

    var new_buf_size = old_buf_size * (2 ** 1);

    bb.data = new bytes(new_buf_size);
    bb.setPosition(new_buf_size - old_buf_size);
  }

  /**
   * Prepare to write an element of `size` after `additional_bytes` have been
   * written, e.g. if you write a string, you need to align such the int length
   * field is aligned to 4 bytes, and the string data follows it directly. If all
   * you need to do is alignment, `additional_bytes` will be 0.
   *
   * @param size This is the of the new element to write
   * @param additional_bytes The padding size
   */
  function prep(Builder storage self, uint32 size, uint32 additional_bytes) {
    if (size > self.minalign) {
      self.minalign = size;
    }

    uint32 align_size = ((~(self.bb.capacity() - self.space + additional_bytes)) + 1) & (size - 1);

    while (self.space < align_size + size + additional_bytes) {
      uint32 old_buf_size = self.bb.capacity();
      growByteBuffer(self.bb);
      self.space += self.bb.capacity() - old_buf_size;
    }

    pad(self, align_size);
  }

  function pad(Builder storage self, uint32 byte_size) {
    for (var i = 0; i < byte_size; i++) {
      self.bb.data[--self.space] = 0;
    }
  }

  function writeInt8(Builder storage self, int8 value) {
    self.bb.writeInt8(self.space -= 1, value);
  }

  function writeInt16(Builder storage self, int16 value) {
    self.bb.writeInt16(self.space -= 2, value);
  }

  function writeInt32(Builder storage self, int32 value) {
    self.bb.writeInt32(self.space -= 4, value);
  }

  function writeInt64(Builder storage self, int64 value) {
    self.bb.writeInt64(self.space -= 8, value);
  }

  function addInt8(Builder storage self, int8 value) {
    prep(self, 1, 0);
    writeInt8(self, value);
  }

  function addInt16(Builder storage self, int16 value) {
    prep(self, 2, 0);
    writeInt16(self, value);
  }

  function addInt32(Builder storage self, int32 value) {
    prep(self, 4, 0);
    writeInt32(self, value);
  }

  function addInt64(Builder storage self, int64 value) {
    prep(self, 8, 0);
    writeInt64(self, value);
  }

  /**
   * Adds on offset, relative to where it will be written.
   *
   * @param value The offset to add.
   */
  function addOffset(Builder storage self, uint32 value) {
    prep(self, 4, 0);
    writeInt32(self, int32(offset(self) - value + 4));
  }

  function addFieldInt8(Builder storage self, uint32 voffset, int8 value, int8 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      addInt8(self, value);
      slot(self, voffset);
    }
  }

  function addFieldInt16(Builder storage self, uint32 voffset, int16 value, int16 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      addInt16(self, value);
      slot(self, voffset);
    }
  }

  function addFieldInt32(Builder storage self, uint32 voffset, int32 value, int32 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      addInt32(self, value);
      slot(self, voffset);
    }
  }

  function addFieldInt64(Builder storage self, uint32 voffset, int64 value, int64 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      addInt64(self, value);
      slot(self, voffset);
    }
  }

  function addFieldOffset(Builder storage self, uint32 voffset, uint32 value, uint32 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      addOffset(self, value);
      slot(self, voffset);
    }
  }

  /**
   * Structs are stored inline, so nothing additional is being added. `d` is always 0.
   */
  function addFieldStruct(Builder storage self, uint32 voffset, uint32 value, uint32 defaultValue) {
    if (self.force_defaults || value != defaultValue) {
      nested(self, value);
      slot(self, voffset);
    }
  }

  /**
   * Structures are always stored inline, they need to be created right
   * where they're used.  You'll get this assertion failure if you
   * created it elsewhere.
   *
   * @param obj The offset of the created object.
   */
  function nested(Builder storage self, uint32 obj) {
    if (obj != offset(self)) {
      throw; // FlatBuffers: struct must be serialized inline.
    }
  }

  /**
   * Should not be creating any other object, string or vector
   * while an object is being constructed
   */
  function notNested(Builder storage self) {
    if (self.isNested) {
      throw; // FlatBuffers: object serialization must not be nested.
    }
  }

  /**
   * Set the current vtable at `voffset` to the current location in the buffer.
   */
  function slot(Builder storage self, uint32 voffset) {
    self.vtable[voffset] = offset(self);
  }

  /**
   * Offset relative to the end of the buffer.
   */
  function offset(Builder storage self) returns (uint32) {
    return self.bb.capacity() - self.space;
  }

  /**
   * Start encoding a new object in the buffer.  Users will not usually need to
   * call this directly. The FlatBuffers compiler will generate helper methods
   * that call this method internally.
   */
  function startObject(Builder storage self, uint32 numFields) {
    notNested(self);
    self.vtable_in_use = numFields;
    for (var i = 0; i < numFields; i++) {
      self.vtable[i] = 0;
    }
    self.isNested = true;
    self.object_start = offset(self);
  }

  /**
   * Finish off writing the object that is under construction.
   *
   * The offset to the object inside `dataBuffer`
   */
  function endObject(Builder storage self) returns (uint32) {
    if (!self.isNested) {
      throw; // FlatBuffers: endObject called without startObject
    }

    addInt32(self, 0);
    var vtableloc = offset(self);

    // Write out the current vtable.
    for (var i = self.vtable_in_use - 1; i >= 0; i--) {
      // Offset relative to the start of the table.
      addInt16(self, int16(self.vtable[i] != 0 ? vtableloc - self.vtable[i] : 0));
    }

    var standard_fields = 2; // The fields below:
    addInt16(self, int16(vtableloc - self.object_start));
    addInt16(self, int16((self.vtable_in_use + standard_fields) * 16));

    // Search for an existing vtable that matches the current one.
    uint32 existing_vtable = 0;
    for (i = 0; i < self.vtables.length; i++) {
      uint32 vt1 = self.bb.capacity() - self.vtables[i];
      uint32 vt2 = self.space;
      int16 len = self.bb.readInt16(vt1);
      if (len == self.bb.readInt16(vt2) && vtableMatch(self, len, vt1, vt2)) {
        existing_vtable = self.vtables[i];
        break;
      }
    }

    if (existing_vtable != 0) {
      // Found a match:
      // Remove the current vtable.
      self.space = self.bb.capacity() - vtableloc;

      // Point table to existing vtable.
      self.bb.writeInt32(self.space, int32(existing_vtable - vtableloc));
    } else {
      // No match:
      // Add the location of the current vtable to the list of vtables.
      self.vtables.push(offset(self));

      // Point table to current vtable.
      self.bb.writeInt32(self.bb.capacity() - vtableloc, int32(offset(self) - vtableloc));
    }

    self.isNested = false;
    return vtableloc;
  }

  function vtableMatch(Builder storage self, int16 len, uint32 vt1, uint32 vt2) internal returns (bool) {
    for (var j = 16; j < len; j += 16) {
      if (self.bb.readInt16(vt1 + j) != self.bb.readInt16(vt2 + j)) {
        return false;
      }
    }
    return true;
  }

  /**
   * Finalize a buffer, poiting to the given `root_table`.
   */
  // FIXME: Support the opt_file_identifier argument.
  function finish(Builder storage self, uint32 root_table) {
    prep(self, self.minalign, 4); // SIZEOF_INT
    addOffset(self, root_table);
    self.bb.setPosition(self.space);
  }

  /**
   * This checks a required field has been set in a given table that has
   * just been constructed.
   */
  function requiredField(Builder storage self, uint32 table, uint32 field) {
    uint32 table_start = self.bb.capacity() - table;
    uint32 vtable_start = table_start - uint32(self.bb.readInt32(table_start));
    bool ok = self.bb.readInt16(vtable_start + field) != 0;

    // If this fails, the caller will show what field needs to be set.
    if (!ok) {
      throw; // FlatBuffers: field must be set;
    }
  }

  /**
   * Start a new array/vector of objects.  Users usually will not call
   * this directly. The FlatBuffers compiler will create a start/end
   * method for vector types in generated code.
   *
   * @param elem_size The size of each element in the array.
   * @param num_elems The number of elements in the array.
   * @param alignment The alignment of the array.
   */
  function startVector(Builder storage self, uint32 elem_size, uint32 num_elems, uint32 alignment) {
    notNested(self);
    self.vector_num_elems = num_elems;
    prep(self, 4, elem_size * num_elems); // SIZEOF_INT
    prep(self, alignment, elem_size * num_elems); // Just in case alignment > int.
  }

  /**
   * Finish off the creation of an array and all its elements. The array must be
   * created with `startVector`.
   *
   * The offset at which the newly created array
   * starts.
   */
  function endVector(Builder storage self) returns (uint32) {
    writeInt32(self, int32(self.vector_num_elems));
    return offset(self);
  }

  /**
   * Encode the string `s` in the buffer using UTF-8.
   *
   * @param s The string to encode.
   */
  function createString(Builder storage self, bytes s) returns (uint32) {
    addInt8(self, 0);
    startVector(self, 1, uint32(s.length), 1);
    self.bb.setPosition(self.space -= uint32(s.length));
    var offset = self.space;
    for (var i = 0; i < s.length; i++) {
      self.bb.data[offset++] = s[i];
    }

    return endVector(self);
  }
}

library ByteBuffer {
  struct ByteBuffer {
    bytes data;
    uint32 position;
  }

  function readInt8(ByteBuffer storage self, uint offset) returns (int8) {
    return int8(readUint8(self, offset));
  }

  function readUint8(ByteBuffer storage self, uint offset) returns (uint8) {
    return uint8(self.data[offset]);
  }

  function readInt16(ByteBuffer storage self, uint offset) returns (int16) {
    return int16(readUint16(self, offset));
  }

  function readUint16(ByteBuffer storage self, uint offset) returns (uint16) {
    return uint16(self.data[offset]) | (uint16(self.data[offset + 1]) * (2 ** 8));
  }

  function readInt32(ByteBuffer storage self, uint offset) returns (int32) {
    return int32(self.data[offset])
      | (int32(self.data[offset + 1]) * (2 ** 8))
      | (int32(self.data[offset + 2]) * (2 ** 16))
      | (int32(self.data[offset + 3]) * (2 ** 24));
  }

  function readUint32(ByteBuffer storage self, uint offset) returns (uint32) {
    return uint32(readInt32(self, offset));
  }

  function readInt64(ByteBuffer storage self, uint offset) returns (int64) {
    return int64(self.data[offset])
      | (int64(self.data[offset + 1]) * (2 ** 8))
      | (int64(self.data[offset + 2]) * (2 ** 16))
      | (int64(self.data[offset + 3]) * (2 ** 24))
      | (int64(self.data[offset + 4]) * (2 ** 32))
      | (int64(self.data[offset + 5]) * (2 ** 40))
      | (int64(self.data[offset + 6]) * (2 ** 48))
      | (int64(self.data[offset + 7]) * (2 ** 56));
  }

  function readUint64(ByteBuffer storage self, uint offset) returns (uint64) {
    return uint64(readInt64(self, offset));
  }

  function writeInt8(ByteBuffer storage self, uint offset, int8 value) {
    self.data[offset] = bytes1(value);
  }

  function writeInt16(ByteBuffer storage self, uint offset, int16 value) {
    self.data[offset] = bytes1(value);
    self.data[offset + 1] = bytes1(value / (2 ** 8));
  }

  function writeInt32(ByteBuffer storage self, uint offset, int32 value) {
    self.data[offset] = bytes1(value);
    self.data[offset + 1] = bytes1(value / (2 ** 8));
    self.data[offset + 2] = bytes1(value / (2 ** 16));
    self.data[offset + 3] = bytes1(value / (2 ** 24));
  }

  function writeInt64(ByteBuffer storage self, uint offset, int64 value) {
    self.data[offset] = bytes1(value);
    self.data[offset + 1] = bytes1(value / (2 ** 8));
    self.data[offset + 2] = bytes1(value / (2 ** 16));
    self.data[offset + 3] = bytes1(value / (2 ** 24));
    self.data[offset + 4] = bytes1(value / (2 ** 32));
    self.data[offset + 5] = bytes1(value / (2 ** 40));
    self.data[offset + 6] = bytes1(value / (2 ** 48));
    self.data[offset + 7] = bytes1(value / (2 ** 56));
  }

  /**
   * Look up a field in the vtable, return an offset into the object, or 0 if the
   * field is not present.
   */
  function offset(ByteBuffer storage self, uint32 bb_pos, uint32 vtable_offset) returns (int16) {
    var vtable = uint32(bb_pos) - uint32(readInt32(self, bb_pos));
    return vtable_offset < uint32(readInt16(self, vtable))
      ? readInt16(self, vtable + vtable_offset)
      : 0;
  }

  /**
   * Initialize any Table-derived type to point to the union at the given offset.
   */
  function union(ByteBuffer storage self, Table.Table t, uint32 offset) internal returns (Table.Table) {
    t.bb_pos = uint32(readInt32(self, offset));
    t.bb = self.data;
    return t;
  }

  /**
   * Create a Solidity string from UTF-8 data stored inside the FlatBuffer.
   * This allocates a new string and converts to wide chars upon each access.
   */
  function toString(ByteBuffer storage self, uint32 offset) returns (byte[]) {
    offset += uint32(readInt32(self, offset));

    var length = readInt32(self, offset);
    var result = new byte[](uint256(length));

    offset += 4; // SIZEOF_INT

    for (var i = 0; i < length; ++i) {
      result[i] = byte(readUint8(self, offset + i));
    }

    return result;
  }

  /**
   * Retrieve the relative offset stored at "offset"
   */
  function indirect(ByteBuffer storage self, uint32 offset) returns (uint32) {
    return offset + uint32(readInt32(self, offset));
  }

  /**
   * Get the start of data of a vector whose offset is stored at "offset" in this object.
   */
  function vector(ByteBuffer storage self, uint32 offset) returns (uint32) {
    return offset + uint32(readInt32(self, offset) + 4); // SIZEOF_INT, data starts after the length
  }

  /**
   * Get the length of a vector whose offset is stored at "offset" in this object.
   */
  function vector_len(ByteBuffer storage self, uint32 offset) returns (uint32) {
    return uint32(readInt32(self, offset + uint32(readInt32(self, offset))));
  }

  function capacity(ByteBuffer storage self) returns (uint32) {
    return uint32(self.data.length);
  }

  function setPosition(ByteBuffer storage self, uint32 pos) internal {
    self.position = pos;
  }

  function has_identifier(ByteBuffer storage self, bytes ident) returns (bool) {
    for (var i = 0; i < 4; i++) {
      if (ident[i] != bytes1(readInt8(self, self.position + 4 + i))) {
        return false;
      }
    }
    return true;
  }
}
