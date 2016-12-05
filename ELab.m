%ELab: Constructs an object of eLab experiment
%
% my_lab = ELab('NAME', 'TYPE', 'ADDRESS') creates an object instance that 
% represents experiemnt with name NAME. The type of connection is
% determined using TYPE switch, which can be either 'usb' or 'ethernet'.
% ADDRESS defines URL of experiment if connection type is 'ethernet' or
% serial communication port if connection type is 'usb'.
% 
% Example:
%      
%        my_lab1 = ELab('exp1','usb','COM1');
%        my_lab2 = ELab('exp2','ethernet','http://mylabaddress.com')
%
% ELab class contains the following public methods:
%       
%        .setDI (see <a href="matlab:help Elab.setDI">Elab.setDI</a>)
%        .setByte (see <a href="matlab:help Elab.setByte">Elab.setByte</a>)
%        .setDAC (see <a href="matlab:help Elab.setDAC">Elab.setDAC</a>)
%        .setData (see <a href="matlab:help Elab.setData">Elab.setData</a>)
%        .setBatch (see <a href="matlab:help Elab.setBatch">Elab.setBatch</a>)
%        .getDI (see <a href="matlab:help Elab.getDI">Elab.getDI</a>)
%        .getDO (see <a href="matlab:help Elab.getDO">Elab.getDO</a>)
%        .getDIByte (see <a href="matlab:help Elab.getDIByte">Elab.getDIByte</a>)
%        .getDOByte (see <a href="matlab:help Elab.getDOByte">Elab.getDOByte</a>)
%        .getADC (see <a href="matlab:help Elab.getADC">Elab.getADC</a>)
%        .getDAC (see <a href="matlab:help Elab.getDAC">Elab.getDAC</a>)
%        .getData (see <a href="matlab:help Elab.getData">Elab.getData</a>)
%        .off (see <a href="matlab:help Elab.off">Elab.off</a>)
%
% Description of each method can be displayed using
%
%        help ELab.[method name]
%
% See also elab_manager


classdef ELab < handle
  
   properties(SetAccess=public)
        SerialObj                   % stores active serial object
        ActiveConfig                % configuration of active experiment
        Batch                       % batching trigger
        ActiveSet                   % active map of I/O interface
        LastIncommingMessage        % last message from experiment
        LastOutgoingMessage         % last message to experiment
   end
    
   properties(SetAccess=public)
        TargetName                  % name of experiment
        ComMode                     % ethernet or usb-serial
        ComPort                     % COM port
        SerialStatus                % status of serial connection
        EthUrl                      % URL of experiment (if ETH used)
   end
   
   properties(Constant)
        COM_BAUD_RATE = 115200      % fixed baud rate for usb-serial
   end
   
   methods(Access=public)
        
       function obj = ELab(target_name, conn_type, varargin)
            % ELab constructor method
            obj.TargetName = target_name;
            obj.ActiveConfig = obj.getTargetConfig(target_name);
            obj.Batch = 0;
            switch conn_type
                case 'ethernet'
                    obj.ComMode = conn_type;
                    obj.EthUrl = varargin{1};
                    if obj.EthUrl(end)~='/'
                       obj.EthUrl = [obj.EthUrl '/']; 
                    end
                    obj.SerialStatus = 'None';
                    obj.ComPort = 'None';
                    obj.ActiveConfig = obj.getTargetConfig(target_name);
                    obj.initActiveSet();
                    obj.applyDefaults();
                    obj.applyActiveSet();
                case 'usb'
                    obj.ComMode = conn_type;
                    obj.SerialStatus = 'Closed';
                    obj.ComPort = varargin{1};
                    obj.ActiveConfig = obj.getTargetConfig(target_name);
                    obj.initActiveSet();
                    obj.applyDefaults();
                    obj.initSerialObject(obj.ComPort);
                    obj.serialConnect();
                    obj.applyActiveSet();
                otherwise
                    error('ELabError:UnknownConnectorType','The specified connector type ''%s'' is not a valid option.\n Type ''help ELab'' to see the list of valid connectors.',conn_type);
            end
       end
       
       function setBatch(obj,value)
            % ELab.setBatch allows to turn ON/OFF the batch operation of
            % communication with experiment. If ON, ELab.setXX methods
            % saves user's requests to active set, but do not send it to
            % experiment. If OFF, each ELab.setXX method invokes a message
            % for experiment. Batching is OFF by default.
            %
            % Example of batching:  
            %       
            %       my_lab.setBatch(1); % set batching ON
            %       my_lab.setData('my_var1',100); % stored to active set
            %       my_lab.setData('my_var2',200); % stored to active set
            %       my_lab.setData('my_var3',300); % stored to active set
            %       my_lab.setBatch(0); % set batching OFF
            %       my_lab.setData('my_var4',400); % all four at once
            
            obj.Batch = value;
       end
       
       function setDI(obj,bit,value)
            % ELab.setDI sets binary value of digital input
            %   my_lab.setDI(BIT,VALUE) sets the binary VALUE [0 or 1] for
            %   digital input BIT [1 to 16].
            
            if (bit>=1 && bit<=8)
                if(length(value)==1 && (value == 1 || value == 0))
                    obj.ActiveSet.DI1(bit) = value;
                else
                    error('ELabError:ArgumentMismatch','The value for digital output must be logical scalar (0 or 1).\n Type ''help ELab.setDI'' for usage info.');
                end
            elseif (bit>8 && bit<=16)
                if(length(value)==1 && (value == 1 || value == 0))
                    obj.ActiveSet.DI2(bit-8) = value;
                else
                    error('ELabError:ArgumentMismatch','The value for digital output must be logical scalar (0 or 1).\n Type ''help ELab.setDI'' for usage info.');
                end
            else 
                warning('ELabWarning:BitIndexOutOfRange','The specified bit index %d is out of range.\n This command will be ignored.',bit);
            end 
            obj.applyActiveSet();
       end
       
       function setByte(obj,byte,value)
            % ELab.setByte sets value of whole input byte at once
            %   my_lab.setByte(BYTE,VALUE) sets byte BYTE to 8-bit VALUE.
            %   VALUE can be either a vector of size 1x8 or decimal number
            %   from 0 to 255.
            %   
            %   Example:
            %           my_lab.setByte(1,[1 1 1 1 0 0 0 0]);
            %           my_lab.setByte(2,255);
            
            len = length(value);
            if(len==1)
                if(value>=0 && value<=255)
                    obj.ActiveSet.(['DI' num2str(byte)]) = dec2bin(value,8)-'0';
                else
                    warning('ELabWarning:ByteValueMismatch','The specified value (%d) for byte %s must be 8-bit decimal (0 to 255). \n This value will be ignored.',value,byte);
                end
            elseif (len>1 && len<=8)
                for i=1:length(value)
                    if (value(i)==0 || value(i)==1)
                        obj.ActiveSet.(['DI' num2str(byte)])(i) = value(i);
                    else
                        warning('ELabWarning:BitValueMismatch','The specified value (%d) for bit %d must be logical (0 or 1). \n This value will be ignored.',value(i),i);
                    end
                end
            else
                warning('ELabWarning:BinaryValueTooLong','The specified length (%d) of value vector is bigger than 8 bits. \n This command will be ignored.',len);
            end
            obj.applyActiveSet();
       end
       
       function setDAC(obj,varargin)
            % ELab.setDAC sets value/s for DAC/s
            %   my_lab.setDAC(CHANNEL,VALUE) sets value VALUE for DAC
            %   channel CHANNEL. VALUE must be a decimal number from 0 to
            %   4095 (12-bit resolution).
            %
            %   my_lab.setDAC(VALUES) sets all 4 DAC channels at once.
            %   VALUES must be a vector of size 1x4 with decimal numbers 
            %   from 0 to 4095.
            %
            %   Example:
            %           my_lab.setDAC(1,2000);
            %           my_lab.setDAC([0 1023 2500 4095]);  
            switch nargin
                case 2
                    value = varargin{1};
                    if length(value)==4
                        for i=1:4
                            if (value(i)>=0 && value(i)<=4095)
                                obj.ActiveSet.DAC(i) = value(i);
                            else
                                warning('ELabWarning:WrongDACChannelValue','The value (%d) specified for DAC channel %d must be in the range 0 to 4095 (12-bit). \n This value will be ignored.',value(i),i);
                            end
                        end
                    else
                        warning('ELabWarning:WrongDACNumber','The number of DAC values specified (%d) must be 4. \n This command will be ignored.',length(value));
                    end
                case 3
                    channel = varargin{1};
                    value = varargin{2};
                    if(channel>=1 && channel<=4)
                        if(value>=0 && value<=4095)
                            obj.ActiveSet.DAC(channel) = value;
                        else
                            warning('ELabWarning:WrongDACChannelValue','The value (%d) specified for DAC channel %d must be in the range 0 to 4095 (12-bit). \n This value will be ignored.',value,channel);
                        end
                    else
                        warning('ELabWarning:WrongDACChannel','The specified DAC channel (%d) must be integer in the range 1 to 4. \n This command will be ignored.',channel);
                    end
                otherwise
                    error('ELabError:WrongNumberOfArguments','The number of arguments for setDAC() method is either 1 or 2.\n Type ''help ELab.setDAC'' for usage info.');
            end     
            obj.applyActiveSet();
       end
       
       function value = getDI(obj, bit)
            % ELab.getDI gets binary value of digital input
            %   my_lab.getDI(BIT,VALUE) gets the binary VALUE [0 or 1] of
            %   digital input BIT [1 to 16].           
            if (bit>=1 && bit<=8)
                value = obj.ActiveSet.DI1(bit);
            elseif (bit>8 && bit<=16)
                value = obj.ActiveSet.DI2(bit-8);
            else 
                warning('ELabWarning:BitIndexOutOfRange','The specified bit index %d is out of range.\n Empty result returned.',bit);
            end
       end
       
       function value = getDO(obj, bit)
            % ELab.getDO gets binary value of digital output
            %   my_lab.getDO(BIT,VALUE) gets the binary VALUE [0 or 1] of
            %   digital output BIT [1 to 16].
            if (bit>=1 && bit<=8)
                value = obj.ActiveSet.DO1(bit);
            elseif (bit>8 && bit<=16)
                value = obj.ActiveSet.DO2(bit-8);
            else 
                warning('ELabWarning:BitIndexOutOfRange','The specified bit index %d is out of range.\n Empty result returned.',bit);
            end
       end
       
       function value = getDOByte(obj, byte)
            % ELab.getDOByte gets state of output digital byte
            %   my_lab.getDOByte(BYTE) gets 1x8 vector of digital output
            %   byte BYTE. Vector contains binary values.
            if (byte>=1 && byte<=2)
                value = obj.ActiveSet.(['DO' num2str(byte)]);
            else 
                warning('ELabWarning:BitIndexOutOfRange','The specified byte index %d is out of range (1 or 2).\n Empty result returned.',byte);
            end
       end
       
       function value = getDIByte(obj, byte)
            % ELab.getDIByte gets state of input digital byte
            %   my_lab.getDIByte(BYTE) gets 1x8 vector of digital input
            %   byte BYTE. Vector contains binary values.
            if (byte>=1 && byte<=2)
                value = obj.ActiveSet.(['DI' num2str(byte)]);
            else 
                warning('ELabWarning:BitIndexOutOfRange','The specified byte index %d is out of range (1 or 2).\n Empty result returned.',byte);
            end
       end
       
       function value = getADC(obj,varargin)
            % ELab.getADC gets value/s for ADC/s
            %   my_lab.getADC(CHANNEL,VALUE) gets value VALUE for ADC
            %   channel CHANNEL. Returned value is decimal number from 0 to
            %   1023 (10-bit resolution).
            %
            %   my_lab.getADC() gets all 16 ADC channels at once.
            %   Returned value is vector of size 1x16 with decimal numbers 
            %   from 0 to 1023.
            %
            %   Example:
            %           my_lab.getADC(1); % returns value of channel 1
            %           my_lab.getADC(); % return all 16 values
            switch nargin
                case 1
                    value = zeros(1,16);
                    for i = 1:16
                        value(i) = obj.ActiveSet.ADC(i);
                    end
                case 2
                    if (varargin{1}>=1 && varargin{1}<=16)
                        value = obj.ActiveSet.ADC(varargin{1});
                    else
                        value = [];
                        warning('ELabWarning:WrongADCChannel','The specified ADC channel (%d) must be integer in the range 1 to 16. \n Empty result returned.',varargin{1});
                    end
                otherwise
                    error('ELabError:WrongNumberOfArguments','The number of arguments for getADC() method is either 0 or 1.\n Type ''help ELab.getADC'' for usage info.');
            end
       end
       
       function value = getDAC(obj,varargin)
            % ELab.getDAC gets value/s for DAC/s
            %   my_lab.getDAC(CHANNEL,VALUE) gets value VALUE for DAC
            %   channel CHANNEL. Returned value is decimal number from 0 to
            %   4095 (12-bit resolution).
            %
            %   my_lab.getDAC() gets all 4 DAC channels at once.
            %   Returned value is vector of size 1x4 with decimal numbers 
            %   from 0 to 4095.
            %
            %   Example:
            %           my_lab.getDAC(1); % returns value of channel 1
            %           my_lab.getDAC(); % return all 4 values
            switch nargin
                case 1
                    value = zeros(1,4);
                    for i = 1:4
                        value(i) = obj.ActiveSet.DAC(i);
                    end
                case 2
                    if (varargin{1}>=1 && varargin{1}<=4)
                        value = obj.ActiveSet.DAC(varargin{1});
                    else
                        value = [];
                        warning('ELabWarning:WrongADCChannel','The specified DAC channel (%d) must be integer in the range 1 to 4. \n Empty result returned.',varargin{1});
                    end
                otherwise
                    error('ELabError:WrongNumberOfArguments','The number of arguments for getDAC() method is either 0 or 1.\n Type ''help ELab.getDAC'' for usage info.');
            end
       end
       
       function value = getData(obj,name)
            % ELab.getData gets engineering representation of signal
            %   my_lab.getData('VARNAME') gets value of variable VARNAME.
            %   Format of returned value depends on experiment's
            %   configuration and it is inherited from active config.
            %
            %   Example:
            %           my_lab.getData('my_var1');
            value = [];
            if(isfield(obj.ActiveConfig.config.IO_map.inputs,name))
                io_dir = 'inputs';
            elseif(isfield(obj.ActiveConfig.config.IO_map.outputs,name))
                io_dir = 'outputs';
            else
                warning('ELabWarning:WrongIOName','The specified I/O name ''%s'' does not correspont with the configuration of target ''%s''',name,obj.TargetName);
                return
            end
            io_conf = obj.ActiveConfig.config.IO_map.(io_dir).(name);
            if(strcmp(io_conf.type.Text,'DAC')||strcmp(io_conf.type.Text,'ADC'))
               io_min = 0;
               io_max = strcmp(io_conf.type.Text,'DAC')*(2^12)+strcmp(io_conf.type.Text,'ADC')*(2^10)-1;
               min = str2double(io_conf.min.Text);
               max = str2double(io_conf.max.Text);
               channel = str2double(io_conf.channel.Text);
               io_value = obj.ActiveSet.(io_conf.type.Text)(channel);
               value = (max-min)/(io_max-io_min)*io_value;
            elseif(strcmp(io_conf.type.Text,'DI'))
               bit_num = str2double(io_conf.bit.Text);
               value = obj.getDI(bit_num);
            elseif(strcmp(io_conf.type.Text,'DO'))
               bit_num = str2double(io_conf.bit.Text);
               value = obj.getDO(bit_num);
            else
                warning('ELabWarning:ConfigWrongIOType','I/O type ''%s'' for I/O name ''%s'' in configuration of target %s does not match any of expected types.',io_conf.type.Text,name,obj.TargetName);
                return
            end
       end
       
       function setData(obj,name,value)
            % ELab.setData sets engineering representation of signal
            %   my_lab.setData('VARNAME',VALUE) sets value VALUE of 
            %   variable VARNAME.
            %   Format of VALUE depends on experiment's
            %   configuration and it is inherited from active config.
            %
            %   Example:
            %           my_lab.setData('my_var1',1); % binary
            %           my_lab.setData('my_var2',123.45); % double
            if(isfield(obj.ActiveConfig.config.IO_map.inputs,name))
                io_conf = obj.ActiveConfig.config.IO_map.inputs.(name);
                if(strcmp(io_conf.type.Text,'DAC'))
                    io_min = 0;
                    io_max = (2^12)-1;
                    min = str2double(io_conf.min.Text);
                    max = str2double(io_conf.max.Text);
                    channel = str2double(io_conf.channel.Text);
                    io_value = round((io_max-io_min)/(max-min)*value);
                    obj.setDAC(channel,io_value);
                elseif(strcmp(io_conf.type.Text,'DI'))
                    bit_num = str2double(io_conf.bit.Text);
                    obj.setDI(bit_num,value);
                else
                    warning('ELabWarning:ConfigWrongIOType','I/O type ''%s'' for I/O name ''%s'' in configuration of target %s does not match any of expected types.',io_conf.type.Text,name,obj.TargetName);
                end
            else
                warning('ELabWarning:WrongIOName','The specified I/O name ''%s'' does not correspont with the configuration of target ''%s''',name,obj.TargetName);
                return
            end
       end
       
       function off(obj)
            % ELab.off resets the active set of experiment to its initial
            % values.
            obj.initActiveSet();
            obj.applyActiveSet();
       end
       
       function close(obj)
            % Closes active connection
            if(strcmp(obj.ComMode,'usb'))
                obj.serialClose();
            elseif(strcmp(obj.ComMode,'ethernet'))
                warning('ELabWarning:CloseEthMode','The communication mode ''%s'' does not require to be closed.',obj.ComMode);
            else
                error('ELabError:UnknownComMode','Communication mode %s is not supported',obj.ComMode);
            end
       end
       
   end
   
   methods(Access=private)
       
       function applyActiveSet(obj)
            % Applies ELab.ActiveSet to experiment.
            if obj.Batch == 0
                out_message = obj.encodeOutgoingMessage();
                if strcmp(obj.ComMode,'usb') 
                    if(strcmp(obj.SerialStatus,'Open'))
                        fprintf(obj.SerialObj,'%s\n',out_message);
                    else
                        warning('ELabWarning:SerialClosed','For some reason the serial interface is closed.');
                    end
                elseif strcmp(obj.ComMode,'ethernet')
                    out = urlread2([obj.EthUrl '?' out_message],'GET');
                    obj.decodeIncommingMessage(strtrim(out));
                else
                    error('ELabError:UnknownComMode','Communication mode %s is not supported',obj.ComMode);
                end
            end
       end
        
       function decodeIncommingMessage(obj,message_hex)
            % Decodes incomming HEX stream and stores it in ELab.ActiveSet
            obj.LastIncommingMessage = message_hex;
            message_bin = obj.hex2bin(message_hex,1);
            obj.ActiveSet.start_byte_out = bin2dec([message_bin(1,:) ...
                                                    message_bin(2,:) ...
                                                   ]);
            obj.ActiveSet.DO1 = [message_bin(3,:) ...
                                 message_bin(4,:) ...
                                ]-'0';
            obj.ActiveSet.DO2 = [message_bin(5,:) ...
                                 message_bin(6,:) ...
                                ]-'0';
            obj.ActiveSet.ADC = [];
            for i = 1:16
                obj.ActiveSet.ADC(i) = bin2dec([message_bin(3+i*4,:) ...
                                                message_bin(4+i*4,:) ...
                                                message_bin(5+i*4,:) ...
                                                message_bin(6+i*4,:) ...
                                               ]);
            end
            obj.ActiveSet.end_byte_out = bin2dec([message_bin(end-1,:) ...
                                                  message_bin(end,:) ...
                                                 ]);
       end
       
       function message_hex = encodeOutgoingMessage(obj)
           % Encodes ELab.ActiveSet to HEX
           dac_hex = dec2hex(obj.ActiveSet.DAC,4);
           message_hex = [ dec2hex(obj.ActiveSet.start_byte_in,2) ...
                           dec2hex(obj.ActiveSet.mode,2) ...
                           obj.bin2hex(obj.ActiveSet.DI1) ...
                           obj.bin2hex(obj.ActiveSet.DI2) ...
                           dac_hex(1,:) ... 
                           dac_hex(2,:) ...
                           dac_hex(3,:) ...
                           dac_hex(4,:) ...
                           dec2hex(obj.ActiveSet.end_byte_in,2) ...
                          ];
            obj.LastOutgoingMessage = message_hex;
       end
       
       function initActiveSet(obj)
            % Initiate ELab.ActiveSet
            DI1 = zeros(1,8);
            DI2 = zeros(1,8);
            DO1 = zeros(1,8);
            DO2 = zeros(1,8);
            DAC = zeros(1,4);
            ADC = zeros(1,16);
            mode = 1;
            start_byte_in = 103;
            start_byte_out = 123;
            end_byte_in = 203;
            end_byte_out = 223;
            active_set_struct = struct( ...
               'DI1',DI1, ...
               'DI2',DI2, ...
               'DO1',DO1, ...
               'DO2',DO2, ...
               'DAC',DAC, ...
               'ADC',ADC, ...
               'mode',mode, ...
               'start_byte_in',start_byte_in, ...
               'start_byte_out',start_byte_out, ...
               'end_byte_in',end_byte_in, ...
               'end_byte_out',end_byte_out ...
               );
            obj.ActiveSet = active_set_struct;                       
       end
       
       function applyDefaults(obj)
            % Applies default values to inputs
            input_map = obj.ActiveConfig.config.IO_map.inputs;
            fields = fieldnames(input_map);
            obj.setBatch(1);
            for fn = fields'
                fname = fn{1};
                default_val = str2double(input_map.(fname).default.Text);
                obj.setData(fname,default_val);
            end
            obj.setBatch(0);
       end
       
       function initSerialObject(obj, com_port)
            % Initiates serial object
            obj.ComPort = com_port;
            obj.SerialObj = serial(com_port);
            set(obj.SerialObj,'BaudRate', obj.COM_BAUD_RATE);
            set(obj.SerialObj,'Terminator','LF');
            obj.SerialObj.BytesAvailableFcnMode = 'terminator';
            obj.SerialObj.BytesAvailableFcn = @(~,evt)obj.decodeIncommingMessage(strtrim(fscanf(obj.SerialObj)));
       end
        
       function serialConnect(obj)
            % Establishes connection via serial interface
            fopen(obj.SerialObj); % this will reset the MCU, so we need to wait a while
            disp('Waiting for connection ...');
            pause(2);
            if(strcmp(obj.SerialObj.status,'open'))
                obj.SerialStatus = 'Open';
                disp('Connection established.')   
            else
                error('ELabError:SerialConnectError','Could not establish the serial connection.\n %s port may be missing or used by other program.',obj.ComPort);    
            end
       end
       
       function serialClose(obj)
            % Closes serial connection
            fclose(obj.SerialObj);
            obj.SerialStatus = 'Closed';
            disp('Connection closed.');
       end
       
   end
   
   methods(Static)
       
        function target_config = getTargetConfig(target_name)
            % Acquires active configuration for experiment
            fname = mfilename('fullpath');
            path_string = fileparts(fname);
            full_path = [path_string filesep 'elab_targets' filesep 'elab_' target_name];
            if(exist(full_path,'dir') == 7)
                target_config = xml2struct([full_path filesep 'config.xml']);
            else 
                error('ELabError:MissingTargetError','Error: %s not found. Use elab_manager to install and manage eLab targets.',target_name);
            end
        end
       
        function out = bin2hex(in)
            nbit=2.^(size(in,2)-1:-1:0);
            out=dec2hex(nbit*in.');
            if(length(out)<2)
                out = ['0' out];
            end
        end
        
        function s = hex2bin(h,N)
            h=h(:);
            if iscellstr(h)
                h = char(h); 
            end
            if isempty(h) 
                s = []; 
                return 
            end
            h = upper(h);
            [m,n]=size(h);
            if ~isempty(find((h==' ' | h==0),1))
                h = strjust(h);
                h(cumsum(h ~= ' ' & h ~= 0,2) == 0) = '0';
            else
                h = reshape(h,m,n);
            end
            sixteen = 16;
            p = fliplr(cumprod([1 sixteen(ones(1,n-1))]));
            p = p(ones(m,1),:);
            s = h <= 64;
            h(s) = h(s) - 48;
            s =  h > 64;
            h(s) = h(s) - 55;
            s = sum(h.*p,2);
            d = s;
            d = double(d);
            [~,e] = log2(max(d));
            s = char(rem(floor(d*pow2(1-max(N,e):0)),2)+'0');
        end
        
    end
    
end