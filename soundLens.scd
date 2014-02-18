
(
		SynthDef.new(\Master, {|amp = 1.0 , inBus = 0|

			var sig;

			sig = In.ar(inBus, 2);
			sig = Limiter.ar(sig, 1.0, 0.005);
			sig = sig * amp;

			Out.ar(0,sig);

		}).send(s);


		SynthDef(\Blurrer, {arg inBus = 0, blurAmt = 0, outBus = 0;

		var sig, smoothfactor, fft;

		sig = In.ar(inBus, 2) + PinkNoise.ar(0.00001).dup;
		sig = Limiter.ar(sig, 1.0, 0.001);
		smoothfactor = pow(blurAmt, 0.35) * 0.97;
		fft = FFT({LocalBuf(2048)}!2, sig);
		sig = IFFT(PV_MagSmooth(fft, smoothfactor));
		Out.ar(outBus, sig);

		}).send(s);


		SynthDef.new(\Bell, {|freq = 440, decay = 2.5, outBus = 0, pan = 0, amp = 0.1|

			var sig, ampenv, freqSpec;

		  ampenv = EnvGen.kr(Env.perc(0.001,decay), doneAction:2);
	  	  sig = SinOsc.ar(freq, 0, ampenv) * AmpCompA.ir(freq, 50);
			sig = Pan2.ar(sig * amp * 0.1, pan);

			Out.ar(outBus,sig);

		}).send(s);


)



//tasks and environment variables

(

	~nBins = 10;
	~masterBus = Bus.audio(s, 2);

	~iniTask = Task({

		~masterSynth.free;
		s.sync;
		~masterSynth = Synth.new(\Master, [\inBus, ~masterBus, \amp, 2]);

		s.sync;
		 // ~fftBufs = ~nBins.collect{ { Buffer.alloc(s, 2048) } !2  };
		s.sync;
		~blurBusses = ~nBins.collect{ Bus.audio(s,2) };
	   s.sync;

	  ~blurSynths = ~blurBusses.collect{|inBus, count|

		Synth.new(\Blurrer, [\inBus, inBus, \blurAmt, count * (1.0/~nBins), \outBus, ~masterBus]);

	   };

	});
)



NetAddr.langPort

//for testing

~iniTask.start;
(
		~nBins.do{|count|

			~blurSynths[count].free;
			//~fftBufs[count].free;
			~blurBusses[count].free;

		};
		~masterSynth.free;
)

Synth.new(\Bell, [\freq,  78.midicps, \decay, 2, \outBus , ~blurBusses[0], \amp, 0.5]);



//the OSC nodes

(

	~oscOut = NetAddr.new("192.168.1.200", 8010);

	~ini.remove;
	~ini=nil;
	~ini = OSCresponderNode(nil, '/init', {|i, r, msg|

		msg.postln;
		~iniTask.start;

	}).add;


	~hammer.remove;
	~hammer=nil;
	~hammer = OSCresponderNode(nil, '/chime', {|i, r, msg|

		var bIndex, outBus, amp, freq, pan;
		//msg.postln;

		bIndex = (msg[4] * ~nBins).floor; //one extra bin for no processing
		freq = msg[2];
		amp = pow(1.0 - msg[4], 1.5);

		outBus = ~blurBusses[bIndex];
		pan = msg[5].linlin(-1.0,1.0,-0.85,0.85);

		if(amp > 0.01){
			Synth.new(\Bell, [\freq,  freq.midicps, \decay, msg[3], \amp, amp ,\outBus , outBus, \pan, pan]);
		};

	}).add;

	~exi.remove;
	~exi =nil;
	~exi = OSCresponderNode(nil, '/exit', {|i, r, msg|

		msg.postln;

		~nBins.do{|count|

			~blurSynths[count].free;
			//~fftBufs[count].free;
			~blurBusses[count].free;


		};

		~blurSynths = nil;
		~fftBufs = nil;
		~blurBusses = nil;
		~masterSynth.free;

	}).add;

	~reqScl.remove;
	~reqScl=nil;
	~reqScl = OSCresponderNode(nil, '/reqScl', {|time, resp, msg|

		var scl, outVals, outMess;

		scl = ScaleInfo.scales.at(msg[1].asSymbol);

		outVals = scl.semitones;
		outVals.size().do{ |count|

			if(count != 0){outMess = outMess ++ ","};
			outMess = outMess ++ outVals[count].asString;

		};

		~oscOut.sendMsg("/newScale", scl.semitones.size, outMess);

	}).add;


)
		