package com.vzan.live.publisher;
import java.util.HashMap;

// Exact JNI names from the supplied APK; implementation remains in its libpush.so.
public class SignUtils {
    private long handle;
    public SignUtils() { handle = _create_parameters_util(); }
    private native long _create_parameters_util();
    private native String _get_parameters_sign(long handle, HashMap<String,String> params);
    private native void _set_parameters_key(long handle, String key);
    public void setKey(String key) { _set_parameters_key(handle, key); }
    public String sign(HashMap<String,String> params) { return _get_parameters_sign(handle, params); }
}
