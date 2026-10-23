package com.godot.game;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
public final class OtaSignature {
    public static boolean verify(byte[] payload, byte[] signature, byte[] publicKey) throws Exception {
        PublicKey key=KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(publicKey));
        Signature verifier=Signature.getInstance("SHA256withRSA");
        verifier.initVerify(key); verifier.update(payload); return verifier.verify(signature);
    }
}
