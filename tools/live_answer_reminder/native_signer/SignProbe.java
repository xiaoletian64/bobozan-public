import java.util.HashMap;
import com.vzan.live.publisher.SignUtils;

public class SignProbe {
    public static void main(String[] args) {
        System.load("/data/local/tmp/answer-libpush.so");
        String timestamp = args[0];
        String uid = args.length > 1 ? args[1] : "";
        String version = args.length > 2 ? args[2] : "260703";
        HashMap<String,String> params = new HashMap<>();
        params.put("uid", uid);
        params.put("deviceType", "1");
        params.put("versionCode", version);
        params.put("timestamp", timestamp);
        params.put("platform", "android_vzanlive");
        SignUtils signer = new SignUtils();
        signer.setKey(version + timestamp);
        System.out.println("SIGN_RESULT " + signer.sign(params));
    }
}
