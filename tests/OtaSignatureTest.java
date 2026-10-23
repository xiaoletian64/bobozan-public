package com.godot.game;
import java.nio.file.*;
import java.security.*;
public final class OtaSignatureTest {
 public static void main(String[] args) throws Exception {
  KeyPairGenerator generator=KeyPairGenerator.getInstance("RSA");generator.initialize(2048);
  KeyPair key=generator.generateKeyPair();byte[] payload="version=12;hash=abc".getBytes("UTF-8");
  Signature signer=Signature.getInstance("SHA256withRSA");signer.initSign(key.getPrivate());signer.update(payload);byte[] signature=signer.sign();
  if(!OtaSignature.verify(payload,signature,key.getPublic().getEncoded()))throw new AssertionError("valid signature rejected");
  payload[0]^=1;
  if(OtaSignature.verify(payload,signature,key.getPublic().getEncoded()))throw new AssertionError("tamper accepted");
  payload[0]^=1;
  if(OtaSignature.verify(payload,signature,generator.generateKeyPair().getPublic().getEncoded()))throw new AssertionError("wrong key accepted");
  System.out.println("PASS: native OTA verifier accepts trusted payload, rejects modified payload and wrong key");
 }
}
