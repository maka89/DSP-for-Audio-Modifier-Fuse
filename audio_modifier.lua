--[[

-------------------------------------------------------------------
Copyright (c) 2025,  Aleksander Kringstad
<https://github.com/maka89>
-------------------------------------------------------------------

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-------------------------------------------------------------------

--]]


-- Calculate length of a table
function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

-- Convert Attack / Release from milliseconds to constants used in exponential smoothing algorithm.
function calc_atk_rel(atk_rel_ms, sample_rate)
	return math.exp(-math.log(9)*1000.0/(atk_rel_ms*sample_rate))
end

-- Linear Interpolation
function linear_interpolation(x,x0,x1,y0,y1)
	return y0 + (x-x0)*(y1-y0)/(x1-x0)

end

-- Clip envelope
-- Values under low_val will be neglected.
function clip(x,low_val)
	return math.max(x-low_val,0.0)

end



--[[

A collection of level detectors. From "Digital Dynamic Range Compressor Design—
A Tutorial and Analysis" by DIMITRIOS GIANNOULIS et al

--Another level detector more suitable for long attacks and short releases. Smooth version.
function process_single_sm_branching(x, atk, rel, buffer)

	ret = 0.0
	if x<=buffer[2] then
		ret = rel*buffer[2]+ (1.0-rel)*x
	else
		ret = atk*buffer[2] + (1.0-atk)*x
	end
	buffer[2] = ret
	return ret
end

--Another level detector more suitable for long attacks and short releases.
function process_single_branching(x, atk, rel, buffer)

	ret = 0.0
	if x<=buffer[2] then
		ret = rel*buffer[2]
	else
		ret = atk*buffer[2] + (1.0-atk)*x
	end
	buffer[2] = ret
	return ret
end


-- Standard Level detector.
function process_single_decoupled(x, atk, rel, buffer)
	y1 = math.max(x,rel*buffer[1])
	buffer[1] = 1.0*y1
	yL = atk*buffer[2]+(1.0-atk)*y1
	buffer[2] = yL

	return yL
end


--]]



-- Standard Level detector. Smooth version.
function process_single_sm_decoupled(x, atk, rel, buffer)
	y1 = math.max(x,rel*buffer[1]+(1.0-rel)*x)
	buffer[1] = 1.0*y1
	yL = atk*buffer[2]+(1.0-atk)*y1
	buffer[2] = yL

	return yL
end




-- audio_samples: table with the audio samples
-- audio_sample_rate: Sample rate of the audio
-- attack: Attack in milliseconds
-- release: Release in milliseconds
-- lookahead: lookahead in milliseconds
-- frame_rate: Frame rate of video
function initialize_buffer(audio_samples, audio_sample_rate, attack, release)
	buffer = {}
	N = tablelength(audio_samples)

	audio_in = {}
	for i =1,N do
		audio_in[i] = audio_samples[i]
	end

	buffer[1] = {audio_in, tablelength(audio_in)} -- Buffer[1] is {incoming audio, length of incoming audio}
	buffer[2] = {{},0} -- Buffer[2] is the calculated audio envelope (Calculated in real time).
	buffer[3] = audio_sample_rate --Buffer[3] is audio sample rate [Hz].
	buffer[4] = {calc_atk_rel(attack,audio_sample_rate),attack} -- Buffer[4] is {exponential moving average constant for attack, attack(ms)}.
	buffer[5] = {calc_atk_rel(release,audio_sample_rate),release} -- Buffer[5] is {exponential moving average constant for release, release(ms)}.
	buffer[6] = {0.0,0.0} --Buffer[6] is the buffer for the level detector.


	--[[
	-- Coefficients related to the low-pass filter.
	fc = 0.5*frame_rate
	c=1.0/math.tan(math.pi*fc/audio_sample_rate)
	buffer[8] = {}
	buffer[8][1] = 1.0/(1.0+math.sqrt(2)*c+c*c)
	buffer[8][2] = 2.0*buffer[8][1]
	buffer[8][3] = 1.0*buffer[8][1]
	buffer[8][4] = 2.0*buffer[8][1]*(1.0-c*c)
	buffer[8][5] = buffer[8][1]*(1.0-math.sqrt(2)*c+c*c)


	buffer[9] = {{0.0,0.0,0.0},{0.0,0.0,0.0},{0.0,0.0,0.0},{0.0,0.0,0.0}} -- Cached y- values for biquad LPF
	--]]

	return buffer

end



function calculate_raw_envelope(t, lookahead, scale, offset, minval, buffer)

	t=t+lookahead/1000.0
	sample_length = buffer[1][2]
	sample_rate = buffer[3]
	attack_ms = buffer[4][2]
	release_ms = buffer[5][2]


	tail = (attack_ms+release_ms)/1000.0



	-- If required, calculate new values of the envelope
	current_time = buffer[2][2]/sample_rate -- Latest calculated time
	while t >= current_time and t <= sample_length/sample_rate + 5.0*tail do
		idx = buffer[2][2]+1

		if buffer[2][2] < buffer[1][2] then
			samp = buffer[1][1][idx]
		else
			samp = 0.0 -- If t > time of audio clip, then calculate the drop off of the envelope anyway.
		end


		ret = process_single_sm_decoupled(math.abs(samp),buffer[4][1],buffer[5][1],buffer[6])
		buffer[2][1][idx]=ret
		buffer[2][2] = idx
		current_time = buffer[2][2]/sample_rate
	end





	-- Interpolate

	-- If t is larger than audio sample length by a significant margin, then just return 0 as the envelope.
	if t > sample_length/sample_rate + 5.0*tail then
		return 0.0
	end

	if t < 0.0 then
		return 0.0
	end

	t_idx = t*sample_rate
	t_idx_m = math.floor(t_idx)

	if t_idx == t_idx_m then  -- If t coincides with the time for an actual sample.
		val = buffer[2][1][t_idx_m]
	else -- Else interpolate between two closest samples
		val = linear_interpolation(t_idx-t_idx_m,0,1,buffer[2][1][t_idx_m],buffer[2][1][t_idx_m+1])
	end

	return scale*clip(val,minval)+offset

end
