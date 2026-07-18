extern "flint" fn host_alloc(size: i32) i32;
extern "flint" fn host_set_result(ptr: i32, len: i32) void;

export fn flint_abi_version() i32 { return 1; }
export fn flint_on_event(in_ptr: i32, in_len: i32) i32 {
    _ = host_alloc;
    if (in_len < 0) return 1;
    host_set_result(in_ptr, in_len);
    return 0;
}
