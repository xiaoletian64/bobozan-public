package com.godot.game;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.system.Os;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import org.json.*;

/** BLE GATT transport with a per-process authenticated loopback bridge to Godot. */
public final class BoboBle {
    static final UUID SERVICE=UUID.fromString("6a914a00-c746-4f03-9b53-0f997e62bd01");
    static final UUID RX=UUID.fromString("6a914a01-c746-4f03-9b53-0f997e62bd01");
    static final UUID TX=UUID.fromString("6a914a02-c746-4f03-9b53-0f997e62bd01");
    static final UUID CCCD=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    static final int REQUEST=7021, MAX=8192;
    final Activity activity;
    final BoboUpdate updater;
    final Handler main=new Handler(Looper.getMainLooper());
    final Map<String,BluetoothDevice> found=new HashMap<>();
    final ArrayDeque<byte[]> outgoing=new ArrayDeque<>();
    final ByteArrayOutputStream received=new ByteArrayOutputStream();
    BluetoothAdapter adapter;
    BluetoothGatt gatt;
    BluetoothGattServer server;
    BluetoothGattCharacteristic writeCharacteristic, notifyCharacteristic;
    BluetoothDevice subscriber;
    BluetoothLeScanner scanner;
    BluetoothLeAdvertiser advertiser;
    ServerSocket listener;
    PrintWriter writer;
    Socket client;
    String token, pending="";
    boolean isHost=false, busy=false, live=false;
    long generation=0;
    int payloadSize=20;
    boolean discovering=false;
    final Map<String,Integer> negotiatedMtu=new HashMap<>();
    public BoboBle(Activity a) { activity=a; updater=new BoboUpdate(a); }
    JSONObject obj(String type) { JSONObject j=new JSONObject(); try{j.put("event",type);}catch(Exception ignored){} return j; }
    void emit(String type,String key,Object value) { JSONObject j=obj(type);try{j.put(key,value);}catch(Exception ignored){} emit(j); }
    synchronized void emit(JSONObject j) { if(writer!=null){writer.println(j.toString());writer.flush();} }
    void error(String message) { emit("error","message",message); }
    public void start() {
        try {
            byte[] b=new byte[24];new SecureRandom().nextBytes(b);token=android.util.Base64.encodeToString(b,android.util.Base64.NO_WRAP);
            listener=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"));
            Os.setenv("BOBO_BLE_PORT",Integer.toString(listener.getLocalPort()),true);
            Os.setenv("BOBO_BLE_TOKEN",token,true);
            Thread thread=new Thread(() -> {
                while(!listener.isClosed()) {
                    try(Socket socket=listener.accept()) {
                        socket.setSoTimeout(5000);
                        BufferedReader input=new BufferedReader(new InputStreamReader(socket.getInputStream(),StandardCharsets.UTF_8));
                        String first=readLimited(input);
                        if(first==null || !token.equals(new JSONObject(first).optString("token"))) continue;
                        socket.setSoTimeout(0);
                        synchronized(this){client=socket;writer=new PrintWriter(new OutputStreamWriter(socket.getOutputStream(),StandardCharsets.UTF_8));}
                        emit("bridge_ready","platform","Android");
                        String line;
                        while((line=readLimited(input))!=null) {
                            JSONObject command=new JSONObject(line);
                            main.post(() -> command(command));
                        }
                    } catch(Exception ignored) {} finally {
                        synchronized(this){writer=null;client=null;}
                        main.post(this::disconnect);
                    }
                }
            },"BoboBleBridge");thread.setDaemon(true);thread.start();
        } catch(Exception e){android.util.Log.e("BoboBle","Bridge initialization failed");}
    }
    String readLimited(Reader r) throws IOException {
        StringBuilder s=new StringBuilder(); int c;
        while((c=r.read())!=-1){if(c=='\n')return s.toString();if(s.length()>=MAX)throw new IOException("frame too large");s.append((char)c);}
        return s.length()==0?null:s.toString();
    }
    boolean allowed() {
        if(Build.VERSION.SDK_INT>=31) {
            for(String p:new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE})
                if(activity.checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED)return false;
        } else if(activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED)return false;
        return true;
    }
    void require(String cmd) {
        if(!allowed()) {
            pending=cmd;
            activity.requestPermissions(Build.VERSION.SDK_INT>=31 ? new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION},REQUEST);
            return;
        }
        BluetoothManager manager=(BluetoothManager)activity.getSystemService(Activity.BLUETOOTH_SERVICE);
        adapter=manager==null?null:manager.getAdapter();
        if(adapter==null){error("本机不支持蓝牙");return;}
        if(!adapter.isEnabled()){error("请在系统设置中打开蓝牙后重试");return;}
        disconnect();
        if(cmd.equals("open_update")) { updater.check(); return; }
            if(cmd.equals("host")) host(manager); else scan();
    }
    public void permissionResult(int request) {
        if(request!=REQUEST)return;
        String cmd=pending;pending="";
        if(allowed()&&!cmd.isEmpty())require(cmd);else error("未获蓝牙权限；可在系统设置中允许，单机仍可使用");
    }
    void command(JSONObject j) {
        try {
            String cmd=j.optString("command");
            if(cmd.equals("open_update")) { updater.check(); return; }
            if(cmd.equals("host")||cmd.equals("scan"))require(cmd);
            else if(cmd.equals("connect"))connect(j.optString("id"));
            else if(cmd.equals("send"))send(j.getJSONObject("packet"));
            else if(cmd.equals("disconnect"))disconnect();
        } catch(SecurityException e){error("蓝牙权限已被撤销，请重新允许");disconnect();}
          catch(Exception e){error("蓝牙操作失败，请重新连接");disconnect();}
    }
    final ScanCallback scanCallback=new ScanCallback(){
        @Override public void onScanResult(int type,ScanResult result){main.post(() -> {
            BluetoothDevice device=result.getDevice();String id=device.getAddress();
            if(found.containsKey(id)||found.size()>=12)return;found.put(id,device);
            JSONObject j=obj("peer");try{j.put("id",id);j.put("name","附近玩家 "+id.substring(Math.max(0,id.length()-5)));}catch(Exception ignored){}emit(j);
        });}
        @Override public void onScanFailed(int code){error("搜索失败（"+code+"），请稍后重试");}
    };
    final AdvertiseCallback advertiseCallback=new AdvertiseCallback(){
        @Override public void onStartSuccess(AdvertiseSettings settings){emit("status","message","房间已创建，等待另一台手机加入");}
        @Override public void onStartFailure(int code){error("本机无法广播房间，请改由对方创建（"+code+"）");}
    };
    void scan(){
        scanner=adapter.getBluetoothLeScanner();if(scanner==null){error("无法启用蓝牙搜索");return;}
        found.clear();scanner.startScan(Collections.singletonList(new ScanFilter.Builder().setServiceUuid(new ParcelUuid(SERVICE)).build()),new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);
        emit("status","message","正在搜索附近房间…");
        final long g=generation;
        main.postDelayed(() -> {if(g==generation&&scanner!=null){stopScan();emit("status","message","搜索结束；未找到时请确认对方已创建房间，并重试");}},15000);
    }
    void stopScan(){if(scanner!=null){scanner.stopScan(scanCallback);scanner=null;}}
    void host(BluetoothManager manager){
        if(!adapter.isMultipleAdvertisementSupported()){error("本机不支持广播房间，请由对方创建，你选择加入");return;}
        isHost=true;server=manager.openGattServer(activity,serverCallback);
        if(server==null){error("无法建立蓝牙房间");return;}
        BluetoothGattService service=new BluetoothGattService(SERVICE,BluetoothGattService.SERVICE_TYPE_PRIMARY);
        writeCharacteristic=new BluetoothGattCharacteristic(RX,BluetoothGattCharacteristic.PROPERTY_WRITE,BluetoothGattCharacteristic.PERMISSION_WRITE);
        notifyCharacteristic=new BluetoothGattCharacteristic(TX,BluetoothGattCharacteristic.PROPERTY_NOTIFY,BluetoothGattCharacteristic.PERMISSION_READ);
        notifyCharacteristic.addDescriptor(new BluetoothGattDescriptor(CCCD,BluetoothGattDescriptor.PERMISSION_READ|BluetoothGattDescriptor.PERMISSION_WRITE));
        service.addCharacteristic(writeCharacteristic);service.addCharacteristic(notifyCharacteristic);server.addService(service);
    }
    void connect(String id){
        BluetoothDevice device=found.get(id);if(device==null){error("房间已失效，请重新搜索");return;}
        stopScan();gatt=device.connectGatt(activity,false,clientCallback,BluetoothDevice.TRANSPORT_LE);
        emit("status","message","正在连接…");
        final long g=generation;
        main.postDelayed(() -> {if(g==generation&&!live){error("连接超时，请重新搜索");disconnect();}},12000);
    }
    void discover(BluetoothGatt g){
        if(g!=gatt||discovering)return;
        discovering=true;
        if(!g.discoverServices()){error("无法发现房间服务，请重试");disconnect();}
    }
    final BluetoothGattCallback clientCallback=new BluetoothGattCallback(){
        @Override public void onConnectionStateChange(BluetoothGatt g,int status,int newState){main.post(() -> {
            if(g!=gatt)return;
            if(status==BluetoothGatt.GATT_SUCCESS&&newState==BluetoothProfile.STATE_CONNECTED){
                g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                if(!g.requestMtu(185)) discover(g);
                main.postDelayed(() -> {if(g==gatt&&!discovering)discover(g);},1500);
            }
            else if(newState==BluetoothProfile.STATE_DISCONNECTED){emit("disconnected","message","对方已断开");disconnect();}
        });}
        @Override public void onMtuChanged(BluetoothGatt g,int mtu,int status){main.post(() -> {
            if(g!=gatt)return;
            if(status==BluetoothGatt.GATT_SUCCESS)payloadSize=Math.max(20,Math.min(185,mtu-3));
            discover(g);
        });}
        @Override public void onServicesDiscovered(BluetoothGatt g,int status){main.post(() -> {
            if(g!=gatt)return;BluetoothGattService s=g.getService(SERVICE);
            if(status!=BluetoothGatt.GATT_SUCCESS||s==null){error("对方不是兼容的波波赞房间");disconnect();return;}
            writeCharacteristic=s.getCharacteristic(RX);notifyCharacteristic=s.getCharacteristic(TX);
            if(writeCharacteristic==null||notifyCharacteristic==null){error("房间协议不完整");disconnect();return;}
            BluetoothGattDescriptor d=notifyCharacteristic.getDescriptor(CCCD);
            if(d==null||!g.setCharacteristicNotification(notifyCharacteristic,true)){error("无法订阅对战数据");disconnect();return;}
            d.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);g.writeDescriptor(d);
        });}
        @Override public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int status){main.post(() -> {
            if(g!=gatt)return;if(status==BluetoothGatt.GATT_SUCCESS){live=true;emit("connected","host",false);}else{error("无法建立双向通道");disconnect();}
        });}
        @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){byte[] value=c.getValue();main.post(() -> {if(g==gatt)accept(value);});}
        @Override public void onCharacteristicWrite(BluetoothGatt g,BluetoothGattCharacteristic c,int status){main.post(() -> {
            if(g!=gatt)return;if(status!=BluetoothGatt.GATT_SUCCESS){error("发送失败，连接已中断");disconnect();return;}busy=false;pump();
        });}
    };
    final BluetoothGattServerCallback serverCallback=new BluetoothGattServerCallback(){
        @Override public void onMtuChanged(BluetoothDevice d,int mtu){main.post(() -> {
            negotiatedMtu.put(d.getAddress(),Math.max(20,Math.min(185,mtu-3)));
            if(d.equals(subscriber))payloadSize=negotiatedMtu.get(d.getAddress());
        });}
        @Override public void onServiceAdded(int status,BluetoothGattService s){main.post(() -> {
            if(server==null||!isHost)return;
            if(status!=BluetoothGatt.GATT_SUCCESS){error("创建房间失败");return;}
            advertiser=adapter.getBluetoothLeAdvertiser();if(advertiser==null){error("本机不能广播房间");return;}
            advertiser.startAdvertising(new AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true).build(),new AdvertiseData.Builder().addServiceUuid(new ParcelUuid(SERVICE)).build(),advertiseCallback);
        });}
        @Override public void onConnectionStateChange(BluetoothDevice d,int status,int newState){main.post(() -> {
            if(subscriber!=null&&subscriber.equals(d)&&newState==BluetoothProfile.STATE_DISCONNECTED){emit("disconnected","message","对方已断开");disconnect();}
        });}
        @Override public void onDescriptorWriteRequest(BluetoothDevice d,int request,BluetoothGattDescriptor descriptor,boolean prepared,boolean response,int offset,byte[] value){main.post(() -> {
            if(server==null)return;
            boolean ok=!prepared&&offset==0&&CCCD.equals(descriptor.getUuid())&&Arrays.equals(value,BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)&&(subscriber==null||subscriber.equals(d));
            if(response)server.sendResponse(d,request,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_FAILURE,offset,null);
            if(ok){boolean first=!live;subscriber=d;payloadSize=negotiatedMtu.getOrDefault(d.getAddress(),20);live=true;if(advertiser!=null)advertiser.stopAdvertising(advertiseCallback);if(first)emit("connected","host",true);}
        });}
        @Override public void onCharacteristicWriteRequest(BluetoothDevice d,int request,BluetoothGattCharacteristic c,boolean prepared,boolean response,int offset,byte[] value){main.post(() -> {
            if(server==null)return;boolean ok=!prepared&&offset==0&&RX.equals(c.getUuid())&&d.equals(subscriber);
            if(response)server.sendResponse(d,request,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_FAILURE,offset,null);
            if(ok)accept(value);
        });}
        @Override public void onNotificationSent(BluetoothDevice d,int status){main.post(() -> {
            if(!d.equals(subscriber))return;if(status!=BluetoothGatt.GATT_SUCCESS){error("发送失败，连接已中断");disconnect();return;}busy=false;pump();
        });}
    };
    void accept(byte[] bytes){
        if(bytes==null)return;
        for(byte b:bytes){
            if(b=='\n'){
                try{JSONObject p=new JSONObject(received.toString("UTF-8"));JSONObject e=obj("packet");e.put("packet",p);emit(e);}catch(Exception e){error("收到损坏的对战数据");disconnect();return;}
                received.reset();
            }else{if(received.size()>=MAX){error("对战消息过大");disconnect();return;}received.write(b);}
        }
    }
    void send(JSONObject packet){
        if(!live){error("尚未连接对手");return;}
        byte[] bytes=(packet.toString()+"\n").getBytes(StandardCharsets.UTF_8);
        if(bytes.length>MAX||outgoing.size()>512){error("蓝牙发送拥塞");disconnect();return;}
        for(int i=0;i<bytes.length;i+=payloadSize)outgoing.add(Arrays.copyOfRange(bytes,i,Math.min(i+payloadSize,bytes.length)));
        pump();
    }
    void pump(){
        if(busy||outgoing.isEmpty()||!live)return;
        byte[] bytes=outgoing.remove();busy=true;
        boolean ok;
        if(isHost){notifyCharacteristic.setValue(bytes);ok=server.notifyCharacteristicChanged(subscriber,notifyCharacteristic,false);}
        else{writeCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);writeCharacteristic.setValue(bytes);ok=gatt.writeCharacteristic(writeCharacteristic);}
        if(!ok){busy=false;error("无法发送对战消息");disconnect();}
    }
    public void disconnect(){
        generation++;live=false;busy=false;discovering=false;payloadSize=20;negotiatedMtu.clear();outgoing.clear();received.reset();found.clear();
        try{stopScan();if(advertiser!=null)advertiser.stopAdvertising(advertiseCallback);if(gatt!=null){gatt.disconnect();gatt.close();}if(server!=null){if(subscriber!=null)server.cancelConnection(subscriber);server.close();}}catch(SecurityException ignored){}
        advertiser=null;gatt=null;server=null;subscriber=null;writeCharacteristic=null;notifyCharacteristic=null;isHost=false;
    }
    public void destroy(){disconnect();try{if(client!=null)client.close();if(listener!=null)listener.close();}catch(IOException ignored){}}
}
