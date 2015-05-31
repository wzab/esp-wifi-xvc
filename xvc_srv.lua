-- a simple xvc server
-- structure implementing the JTAG server
-- For ISE server should be defined as:
-- xilinx_xvc host=172.200.1.23:6767 maxpacketsize=1024 disableversioncheck=true
-- Definition of pins used for JTAG
TCK=6 -- GPIO 12
TMS=7 -- GPIO 13
TDI=5 -- GPIO 14
TDO=0 -- GPIO 16
gpio.mode(TCK,gpio.OUTPUT)
gpio.mode(TMS,gpio.OUTPUT)
gpio.mode(TDI,gpio.OUTPUT)
gpio.mode(TDO,gpio.INPUT)

jtag_connected = 0
thresh = 10
count = 0
buf_in = ""

function jtag_start()
  count = 0
  jtag_connected = 1
  buf_in = ""
end

function jtag_stop()
  count = 0
  jtag_connected = 0
  buf_in = ""
end

-- Function pulse uses the global buffer buf_in
-- index i1 points to the begining of the TMS data
-- index i2 points to the begining of the TDI data
-- len - defines number of bits to be shifted
function pulse(i1,i2,len)
  dout=""
  obyte=0
  mask=1
  a=tmr.now()
  for i=1,len do
    if bit.band(buf_in:byte(i2),mask)~=0 then
       gpio.write(TDI,gpio.HIGH)
    else
       gpio.write(TDI,gpio.LOW)
    end
    if bit.band(buf_in:byte(i1),mask)~=0 then
       gpio.write(TMS,gpio.HIGH)
    else
       gpio.write(TMS,gpio.LOW)
    end
    if gpio.read(TDO)==1 then
       obyte = bit.bor(obyte,mask)
    end
    gpio.write(TCK,gpio.HIGH)
    mask = bit.lshift(mask,1)
    if mask==256 then
      i1 = i1 + 1
      i2 = i2 + 1
      mask = 1
      dout = dout .. string.char(obyte)
      obyte = 0
      tmr.wdclr()
    end
    gpio.write(TCK,gpio.LOW)
  end
  -- Add the last, uncompleted byte to the output data
  if mask ~= 1 then
    dout = dout .. string.char(obyte)
  end
  b=tmr.now()
  print("time="..tostring(b-a))
  print("heap="..tostring(node.heap()))
  return dout
end
 

function jtag_feed(c,new_data)
  buf_in = buf_in .. new_data
  -- check if there is a known command at the begining of the buffer
  if buf_in:sub(1,8)=="getinfo:" then 
    print("received getinfo\n")
    -- Service getinfo command
    c:send("xvcServer_v1.0:512\n")
    -- Remove the command from the buffer
    buf_in = buf_in:sub(9,-1)
    return true
  elseif buf_in:sub(1,7)=="settck:" then
    -- Service settck command
	   print("received settck\n")
        if buf_in:len() >= 11 then
       -- Currently we simply claim, that we have set the clock
       -- period, even though it doesn't work!
       fck=buf_in:sub(8,11)
       -- We accept only 1000Hz
       fck=string.char(0x40)..string.char(0x42)..string.char(0x0f)..string.char(0)
       c:send(fck)
       -- What really should be done:
       -- Read the TCK period
       -- Program the new clock frequency
       -- Prepare and send the answer
	   -- Remove the command from the buffer
	   buf_in = buf_in:sub(12,-1)
    end
    return true
  elseif buf_in:sub(1,6)=="shift:" then
    -- Service shift command
    if buf_in:len() >= 10 then
       -- Read the length
       length=buf_in:byte(7)+256*buf_in:byte(8)+65536*buf_in:byte(9)+16777216*buf_in:byte(10)
       print("received shift ".. tostring(length) .." bits\n")
       -- Calculate length in bytes
       blen=math.floor((length+7)/8)
       -- Check if the whole vector is received
       if buf_in:len() >= 10+2*blen then
         -- Shift the whole vector
         dout = pulse(11,11+blen,length)
         -- Send the results
         c:send(dout)
         -- remove the command from the buffer
         buf_in = buf_in:sub(10+2*blen+1,-1)      
       end
    end 
  end
end

s=net.createServer(net.TCP,1000)
s:listen(6767,function(c)
    -- Check, if we can accept a client
    if jtag_connected > 0 then
     print("Other client already connected\n")
     c:close()
     return
    else
     print("Client connected\n")
     jtag_start()
    end
    c:on("receive",function(c,l)
          jtag_feed(c,l)          
    end)
    c:on("disconnection",function(c)
      print("Client disconnected\n")
      jtag_stop()      
  end)
end)


