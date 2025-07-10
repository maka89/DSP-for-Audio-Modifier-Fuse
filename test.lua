require "/audio_modifier"

function write_to_file(x,y,length,fn)
	local f = assert(io.open(fn,"w"))
	for i=1,length do
		f:write(tostring(x[i]).."; "..tostring(y[i]).." \n")
	end
	f:close()

end


function test()
	sample_rate = 44100
	length = math.floor(3.0*sample_rate)
	atk_ms = 50.0
	rel_ms = 300.0
	lookahead = 25.0
	scale = -1
	offset= 0.0
	minval = -0.5
	-- Generate some "audio" data
	x = {}
	t0 = {}
	for i =1,length do
		if i < math.floor(1.0*sample_rate) then
			x[i] = 0.0
		elseif i >= math.floor(1.0*sample_rate) and i < math.floor(2.0*sample_rate) then
			x[i] = math.sin(2.0*math.pi*200.0*i/sample_rate)
		else
			x[i] = 3.0*math.sin(2.0*math.pi*200.0*i/sample_rate)
		end
		t0[i]= i/sample_rate
	end



	frame_rate = 24.0
	-- Process data
	buffer = initialize_buffer(x,sample_rate,atk_ms,rel_ms,0.0)
	y={}
	ts = {}
	tmax = 4.0
	len2 = math.floor(tmax*frame_rate)

	for i=1, len2 do
		t = i/frame_rate
		ts[i] = 1.0*t
		y[i]= calculate_raw_envelope(t,lookahead,scale,offset, minval, buffer)
	end

	--Write to file

	write_to_file(t0,x,length,"C:\\Users\\aleks\\Desktop\\luatest\\test_x.txt")
	write_to_file(ts,y,len2,"C:\\Users\\aleks\\Desktop\\luatest\\test_y.txt")


end

test()
