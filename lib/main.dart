import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRender = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRender = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;

  WebSocketChannel? _webSocketChannel;

  List<RTCIceCandidate> icecandidateHoldList = [];

  @override
  void initState() {
    super.initState();
    connectWebSocketServer();
    _localRender.initialize();
    _remoteRender.initialize();
  }

  void connectWebSocketServer(){
    LogUtil.i(TAG, "connectWebSocketServer");
    const String wsUrl = "ws://10.242.142.129:9999/signal";

    _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _webSocketChannel?.stream.listen((message) { 
      // LogUtil.i(TAG, "get message from websocket:");
      // LogUtil.i(TAG, message.runtimeType.toString());
      Map<String,dynamic> dataMap = json.decode(message);
      String cmd = dataMap['cmd'];
      // LogUtil.i(TAG, "websocket get cmd: $cmd data: ${dataMap['data'].toString()}");
      handlSignalEvent(cmd , dataMap);
    });
  }

  void handlSignalEvent(String cmd ,Map<String , dynamic> data){
      switch(cmd){
        case "hello":
        break;
        case "offer":
        handleOffer(data);
        break;
        case "answer":
        handleAnswer(data);
        break;
        case "icecandidate":
        handleIceCandidate(data);
        break;
        case "close":
        handleClose(data);
        break;
        default:
        break;
      }//end switch
  }

  Future<RTCPeerConnection> buildPeerConnection() async{
    var configuration = <String , dynamic>{};
    const iceServer = {
      "urls" : "turn:101.34.23.152:3478",
      "username": "panyi",
      "credential": "123456"
    };
    configuration['iceServers'] = [iceServer];
    configuration['iceTransportPolicy'] = "relay";
    var pc = await createPeerConnection(configuration);
    return pc;
  }

  @override
  void dispose() {
    super.dispose();
    _localStream?.dispose();
  }

  void startOrCloseRtc(){
    LogUtil.i(TAG , "$isStart");
    if(isStart){
      hangUp(true);
    }else{
      makeCall();
    }

    setState(() {
      isStart = !isStart;
    });
  }

  void hangUp(bool sendCloseSignal){
    LogUtil.i(TAG, "make hangUp");
    _localStream?.dispose();
    _localRender.srcObject = null;

    _remoteStream?.dispose();
    _remoteRender.srcObject = null;

    if(_peerConnection!= null){
      _peerConnection?.close();
      _peerConnection = null;
    }

    setState(() {
      isStart = false;
    });

    if(sendCloseSignal){
      var closeData = buildSignalData("close", {});
      sendSignal(closeData);
    }
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
    startCameraPreview(stream);
    startRtc();
  }

  void handleOfferStartedStream(MediaStream stream , Map<String , dynamic> jsonData) async{
    startCameraPreview(stream);

    _peerConnection ??= await buildPeerConnection();

    LogUtil.i(TAG, "add local tracks");
    _localStream?.getTracks().forEach((track)=>_peerConnection?.addTrack(track , _localStream!));

    LogUtil.i(TAG, "add PeerConnectionListener");
    addPeerConnectionListener();

    Map<String , dynamic> mapData = jsonData['data'];
    LogUtil.i(TAG, "remote description : $mapData");
    _peerConnection
      ?.setRemoteDescription(RTCSessionDescription(mapData['sdp'], mapData['type']))
      .then((value){
        if(icecandidateHoldList.isNotEmpty){
          for (var ice in icecandidateHoldList) {
            LogUtil.i(TAG, "add Candidate ${ice.candidate}");
            _peerConnection?.addCandidate(ice);
          }
          icecandidateHoldList.clear();
        }
      });

    RTCSessionDescription? answer = await _peerConnection?.createAnswer();
    if(answer == null){
      return;
    }

    LogUtil.i(TAG, "set answer");
    _peerConnection?.setLocalDescription(answer);

    var answerData = buildSignalData("answer", answer.toMap());
    sendSignal(answerData);

    //ui update
    setState(() {
      isStart = true;
    });

  }

  void startCameraPreview(MediaStream stream){
    _localStream = stream;
    _localRender.srcObject = _localStream;
    setState(() {
    });
  }

  Map<String , dynamic> buildSignalData(String cmd , dynamic data){
    Map<String , dynamic> result = {};
    result['cmd'] = cmd;
    result['data'] = data;
    return result;
  }

  void sendSignal(Map<String , dynamic> msg){
    var strMsg = json.encode(msg);
    _webSocketChannel?.sink.add(strMsg);
  }

  void startRtc() async{
    _peerConnection ??= await buildPeerConnection();
    LogUtil.i(TAG, "add tracks");
    _localStream?.getTracks().forEach((track)=>_peerConnection?.addTrack(track , _localStream!));

    LogUtil.i(TAG, "add PeerConnectionListener");
    addPeerConnectionListener();

    LogUtil.i(TAG, "try get offer");
    RTCSessionDescription? offer = await _peerConnection?.createOffer();

    _peerConnection?.setLocalDescription(RTCSessionDescription(offer?.sdp, offer?.type));
    var offerData = buildSignalData("offer", offer?.toMap());
    // LogUtil.i(TAG, "offer offerData: $offerData}");
    sendSignal(offerData);
  }

  void addPeerConnectionListener(){
    _peerConnection?.onIceCandidate =(candidate){
      var candidataMap = candidate.toMap();
      var iceData = buildSignalData("icecandidate", candidataMap);
      LogUtil.i(TAG , "will send onIceCandidate $iceData");
      sendSignal(iceData);
    };

    _peerConnection?.onTrack = (trackEvent) {
      LogUtil.i(TAG, "remote onTrack");
      // if(trackEvent.streams.isNotEmpty){
      //   _remoteStream = trackEvent.streams[0];
      //   _remoteRender.srcObject = _remoteStream;
      //   setState(() {
      //   });
      // }
    };

    _peerConnection?.onAddStream =(stream) {
      LogUtil.i(TAG, "remote onAddStream");
      _remoteStream = stream;
      _remoteRender.srcObject = _remoteStream;
      setState(() {
      });
    };
  }

  void handleOffer(Map<String , dynamic> jsonData) async{
    LogUtil.i(TAG, "handle offer");

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': true
    };

    navigator.mediaDevices.getUserMedia(mediaConstraints)
      .then((stream) => handleOfferStartedStream(stream , jsonData))
      .catchError((err){
        LogUtil.i(TAG, "get user media error $err");
      });
  }

  void handleAnswer(Map<String , dynamic> jsonData) async{
    LogUtil.i(TAG, "handle answser");
    if(_peerConnection == null){
      return;
    }

    var data = jsonData['data'];
    _peerConnection!
    .setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']))
    .then((value) => LogUtil.i(TAG, "set remote success"))
    .onError((error, stackTrace) => LogUtil.i(TAG, "set remote failed $error"));
  }

  void handleIceCandidate(Map<String , dynamic> jsonData){
    LogUtil.i(TAG, "handleIceCandidate added! pc is null? ${_peerConnection == null}");
    var map = jsonData['data'];
    if(map == null){
      return;
    }

    RTCIceCandidate ice = RTCIceCandidate(map['candidate'], 
      map['sdpMid'], map['sdpMLineIndex']);
    
    if(_peerConnection == null){
      icecandidateHoldList.add(ice);
    }else{
      _peerConnection?.addCandidate(ice);
    }
  }

  void handleClose(Map<String , dynamic> data){
    hangUp(false);
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
