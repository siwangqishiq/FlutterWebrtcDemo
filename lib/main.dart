import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'log.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Webrtc Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isStart = false;
  // ignore: constant_identifier_names
  static const String TAG = "webrtc";

  MediaStream? _localStream;
  final RTCVideoRenderer _localRender = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRender = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;

  @override
  void initState() {
    super.initState();
    _localRender.initialize();
  }

  Future<RTCPeerConnection> buildPeerConnection() async{
    var configuration = <String , dynamic>{};
    return await createPeerConnection(configuration);
  }

  @override
  void dispose() {
    super.dispose();
    _localStream?.dispose();
  }

  void startOrCloseRtc(){
    LogUtil.i(TAG , "$isStart");
    if(isStart){
      hangUp();
    }else{
      makeCall();
    }

    setState(() {
      isStart = !isStart;
    });
  }

  void hangUp(){
    LogUtil.i(TAG, "make hangUp");
    _localStream?.dispose();
    _localRender.srcObject = null;
  }

  void makeCall(){
    LogUtil.i(TAG, "make call");

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': true
    };

    navigator.mediaDevices.getUserMedia(mediaConstraints)
      .then((stream) => handleLocalStream(stream))
      .catchError((err){
        LogUtil.i(TAG, "get user media error $err");
      });
  }

  void handleLocalStream(MediaStream stream){
    _localStream = stream;
    _localRender.srcObject = _localStream;
    setState(() {
    });
    startRtc();
  }

  void startRtc(){

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Stack(
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: RTCVideoView(
                _remoteRender,
                mirror: true,
              ),
            ),
            Align(
              alignment:Alignment.topRight,
              child: SizedBox(
                width: 100,
                height: 180,
                child: RTCVideoView(
                  _localRender,
                  mirror: true,
                ),
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: startOrCloseRtc,
        backgroundColor: isStart?Colors.red: Colors.blue,
        child: isStart?const Icon(Icons.call_end):const Icon(Icons.call),
      ), 
    );
  }
}
