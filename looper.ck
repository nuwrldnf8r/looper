//global
0::second => dur zeroTime;

/*
TODO:
- see what using different voices for each overdub does
- if that works - build in undo when in overdub mode
- look at working out an offset for each track, so when we stop all we can stop play as well, and then they all start again at the same time.
- build stop all, and play all buttons
- expand to 12 tracks (or 8, and keep each looper to 4) and use a slider to fade between the two
- create a method to allow a track to be in both 'decks'

*/

class Loop{
	LiSa loop;
	0::second => dur _zeroTime;
	0 => int _status;
	time _start;
	0 => int _started;
	1 => int _bars;
	_zeroTime => dur _loopLen;
	float _volume;
	Gain myGain;
	
	fun void init(Gain input, int bars) {
	    60::second => loop.duration;
	    1 => loop.play;
	    1 => loop.loop;
	    1 => loop.loopRec;
	    1 => loop.maxVoices;
	    bars => _bars;
	    1.0 => _volume;
	    1.0 => loop.feedback;
	    input => loop => dac;
	}

	fun void setBars(int bars){
		if(_started==0){
			if(bars!=_bars) <<< "set bars to: ", bars >>>;
			bars => _bars;
		}
	}

	fun int status(){
		return _status;
	}

	fun int bars(){
		return _bars;
	}

	fun dur duration(){
		return now - _start;
	}

	fun int started() {
		return _started;
	}

	fun void record(){
		<<< "recording" >>>;
		if(_started==0){
			(0, _volume) => loop.voiceGain;
			_zeroTime => loop.playPos;
			loop.playPos() => loop.recPos;
			1 => _started;
			now => _start;
		}

		1 => _status;
		1 => loop.record;
		1 => loop.loopRec;
	}

	fun void overdub(){
		<<< "overdub" >>>;
		loop.playPos() => loop.recPos;
		2 => _status;
		1 => loop.record;
		1 => loop.loopRec;
	}

	fun void play(){
		<<< "play" >>>;
		(0, _volume) => loop.voiceGain;
		3 => _status;
		0 => loop.record;
		0 => loop.loopRec;
	}

	fun void stop(){
		<<< "stop" >>>;
		0 => _status;
		0 => loop.record;
		0 => loop.loopRec;
		(0, 0) => loop.voiceGain;
	}

  	fun void volume(float value) {
  		value => _volume;
		(0, _volume) => loop.voiceGain;
	}

	fun void setLength(dur barLen){
		if(_loopLen==_zeroTime){
			<<< "setting len" >>>;
			barLen * _bars => _loopLen;
			_loopLen => loop.loopEnd;
			_loopLen => loop.loopEndRec;
		}
	}

	fun void clear(){
		<<< "Clearing" >>>;
		loop.clear();
		0 => _started;
	}

}

zeroTime => dur barLen;
6 => int loopsCount;

Loop loops[loopsCount];

//midi. (eventually pull from some kind of config)
33 => int pedal1Start;
23 => int pedal2Start;
2 => int volStart;
14 => int barsStart;

time pedalStart;

0 => int midiDevice;
if (me.args()) {
  me.arg(0) => Std.atoi => midiDevice;
}

MidiIn midiIn;
MidiMsg msg;
// also need to do midi out

if (!midiIn.open(midiDevice)) {
  <<< "couldn't open midi device ", midiDevice >>>;
  me.exit();
}

Gain inputGain, passThrough;
1.0 => inputGain.gain;
1.0 => passThrough.gain;
adc => inputGain;
adc => passThrough => dac;

0 => int currentLoop;

for (0 => int i; i < loopsCount; i++) {
  loops[i].init(inputGain,1);
}

fun int getActiveLoops(){
	0 => int active;
	for (0 => int i; i < loopsCount; i++) {
  		if(loops[i].started()>0){
  			active++;
  		}
	}
	return active;
}

fun void resetAll(){
	for (0 => int i; i < loopsCount; i++) {
		new Loop @=> loops[i];
		loops[i].init(inputGain,1);
	}
}

fun dur getbarLen(int firstLoop){
	<<< "getting barlen" >>>;
	loops[firstLoop] @=> Loop loop;
	loop.duration()/loop.bars() => barLen; 
	loop.setLength(barLen);
}

fun void processCurrent(){
	loops[currentLoop] @=> Loop current;
	if(current.status()==1 && barLen==zeroTime) getbarLen(currentLoop);
	if(current.status()>0) current.play();
}

fun void pedal1(int loopNum, int data){
	
	if(data==127){
		if(loopNum!=currentLoop) processCurrent();		
		loops[loopNum] @=> Loop loop;
		loop.status() => int status;
		<<< "status: ", status >>>;
		if(status==1 &&  barLen==zeroTime){
			getbarLen(currentLoop);
			loop.overdub();
		}
		else if(status==1){
			loop.play();
		}
		else if(status==2) loop.play();
		else if(status==3) loop.overdub();
		if(status==0){
			<<< "barlen: ", barLen >>>;
			if(barLen!=zeroTime) loop.setLength(barLen);
			if(loop.started()==1) loop.play();
			else loop.record();
		}
		
	}

}

fun void pedal2(int loopNum, int data){
	if(data==127) now => pedalStart;
	loops[loopNum] @=> Loop loop;
	loop.status() => int status;
	if(status==0){
		1::second => dur hold;
		if(data==0 && now - pedalStart >= hold){
			loop.clear();
			loop.bars() => int bars;
			new Loop @=> loops[loopNum];
			loops[loopNum].init(inputGain,1);
			loops[loopNum].setBars(bars);
			if(getActiveLoops()==0){
				<<< "fresh start" >>>;
				zeroTime => barLen;
				resetAll();
			}
		}
	}
	else{
		if(data==127){
			loop.stop();
		}
	}
}

fun void volume(int loopNum, int vol){
	vol => float fvol;
	fvol/127 => float _vol;
	loops[loopNum].volume(_vol);
}

fun void bars(int loopNum, int bars){
	bars/7 + 1 => int _bars;
	//need to somehow link this to barlen so we never run out of sample space.
	loops[loopNum].setBars(_bars);
}

while (true) {
	midiIn => now;
	while (midiIn.recv(msg)) {
		if(msg.data2 >= pedal1Start && msg.data2 < pedal1Start + loopsCount){
			//pedal 1
			pedal1(msg.data2-pedal1Start,msg.data3);
		}
		else if(msg.data2 >= pedal2Start && msg.data2 < pedal2Start + loopsCount){
			//pedal 2
			pedal2(msg.data2-pedal2Start,msg.data3);
		}
		else if(msg.data2 >= volStart && msg.data2 < volStart + loopsCount){
			//volume
			volume(msg.data2-volStart,msg.data3);
		}
		else if(msg.data2 >= barsStart && msg.data2 < barsStart + loopsCount){
			//bars
			bars(msg.data2-barsStart,msg.data3);
		}
	}

}

