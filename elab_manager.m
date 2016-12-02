function elab_manager(command, varargin)
% eLab manager
%
% Supported commands:
%     elab_manager list                     // list available targets
%     elab_manager install [target_name]      // install target
%     elab_manager install all              // install all avail. targets
%     elab_manager open [target_name]         // open target
%     elab_manager showio [target_name]       // show IO config. of target
    
    available_repos = {};
               
    switch lower(command)
        case 'install'
            [repos_urls,repos_count] = loadContents('repositories.txt');
            repo_index = 0;
            target_name = varargin{1};
            for i = 1:repos_count                
                available_repos{i} = getRepoContents(repos_urls{i});
                names = fieldnames(available_repos{i}.contents);
                for j = 1:length(names)
                    if(strcmp(names{j},target_name))
                        repo_index = i;
                    end
                end
            end
            if(repo_index>0)
                fprintf('Do you want to install eLab target ''%s''? ',target_name);
                c = input('[y/n]\n','s');
                if(strcmpi(c,'y'))
                    success = installTarget(target_name,repo_index);
                    if(success)
                        fprintf('ELab target ''%s'' installed successfuly.\n',target_name);
                    end
                else
                    disp('Installation aborted.');
                end
            else
                warning('ELabManagerWarning:MissingTargetWarning','Target ''%s'' not found in any repository. Check file ''repositories.txt'' if desired path exists.',target_name);
            end
        case 'list'
            [repos_urls,repos_count] = loadContents('repositories.txt');
            for i = 1:repos_count
                fprintf('------------------Repository %d-----------------\n',i);
                fprintf('URL: %s \n',repos_urls{i});
                fprintf('-----------------------------------------------\n');
                fprintf('Target      Ver.    Inst.  I/O   Description\n\n'); % 16 10 16               
                available_repos{i} = getRepoContents(repos_urls{i});
                names = fieldnames(available_repos{i}.contents);
                for j = 1:length(names)
                    printCommandLink(names{j},['elab_manager install ' names{j}]);
                    fillSpace(names{j},12);
                    version = available_repos{i}.contents.(names{j}).version.Text;
                    fprintf('%s',version);
                    fillSpace(version,8);
                    is_installed = isInstalled(names{j});
                    if is_installed
                        installed = 'yes';
                        show_io = getCommandLink('show',['elab_manager showio ' names{j}]);
                    else
                        installed = 'no';
                        show_io = getCommandLink('N/A ','fprintf(''\nTo show I/O interface, package must be installed first.\n'')');
                    end
                    fprintf('%s',installed);
                    fillSpace(installed,7);
                    fprintf('%s',show_io);
                    fillSpace('    ',6);
                    descr = available_repos{i}.contents.(names{j}).description.Text;
                    fprintf('%s',descr);
                    fprintf('\n');
                end            
                fprintf('-----------------------------------------------\n');
            end
            fprintf('To install selected target, click on link\n or run command: elab_manager install [target_name]\n');
        case 'open'
            target_name = varargin{1};
            fname = mfilename('fullpath');
            path_string = fileparts(fname);
            full_path = [path_string filesep 'elab_targets' filesep 'elab_' target_name];
            if(exist(full_path,'dir') == 7)
                edit([full_path filesep 'demos' filesep 'blank_ethernet']);
                edit([full_path filesep 'demos' filesep 'blank_usb']);
                open([full_path filesep 'library' filesep target_name '_blank.mdl']);
            else 
                error('ELabManagerError:MissingTargetError','Error: %s not found. Use elab_manager to install and manage eLab targets.',target_name);
            end
        case 'showio'
            target_name = varargin{1};
            fname = mfilename('fullpath');
            path_string = fileparts(fname);
            full_path = [path_string filesep 'elab_targets' filesep 'elab_' target_name];
            if(exist(full_path,'dir') == 7)
                config = xml2struct([full_path filesep 'config.xml']);
                printIOTable(config);
            else 
                error('ELabManagerError:MissingTargetError','Error: %s not found. Use elab_manager to install and manage eLab targets.',target_name);
            end
        otherwise
            disp('unknown command');
    end
    
    function success = installTarget(target_name,repo_index)
        current_dir = fileparts(which(mfilename));
        target_url = available_repos{repo_index}.contents.(target_name).url.Text;
        [temp_path,status] = urlwrite(target_url,[current_dir filesep 'temp_target.zip']);
        if(~status)
            warning('ELabManagerWarning:DownloadFailure','Target ''%s'' could not be downloaded from repository.',target_name);
            success = 0;
            return
        end
        unzip(temp_path,[current_dir filesep 'elab_targets' filesep]);
        delete(temp_path);
        if(exist([current_dir filesep 'elab_targets' filesep 'elab_' target_name],'dir') == 7)
            success = 1;
            fprintf('Add target''s directory to permanent path?\n');
            fprintf('%s \n',[current_dir filesep 'elab_targets' filesep 'elab_' target_name]);
            fprintf('If ''NO'' option is selected, it will be added to temporary path.\n [y,n]?\n');
            c = input('','s');
            if(strcmpi(c,'y'))
                add2path([filesep 'elab_targets' filesep 'elab_' target_name],1);
                fprintf('%s \n',[current_dir filesep 'elab_targets' filesep 'elab_' target_name]);
                fprintf('Added to permanent path.\n')
            else
                add2path([filesep 'elab_targets' filesep 'elab_' target_name],0);
                fprintf('%s \n',[current_dir filesep 'elab_targets' filesep 'elab_' target_name]);
                fprintf('Added to temporary path.\n')
            end
        else
            success = 0;
            warning('ELabManagerWarning:UnzipFailure','An error occured during extraction of archive %s.',temp_path);
        end
    end

    function out = isInstalled(target_name)
            fname = mfilename('fullpath');
            path_string = fileparts(fname);
            full_path = [path_string filesep 'elab_targets' filesep 'elab_' target_name];
            if((exist(full_path,'dir') == 7)&&(exist([full_path filesep 'config.xml'],'file') == 2))
                out = 1;
            else
                out = 0;
            end
    end

    function printIOTable(config)
        fprintf('-----------------------------------------------\n');
        fprintf('%s signal table\n',config.config.name.Text);
        fprintf('-----------------------------------------------\n');
        fprintf('Inputs (control signals):\n');
        fprintf('%s','name');
        fillSpace('name',16);
        fprintf('%s','type');
        fillSpace('type',5);
        fprintf('%s','range');
        fillSpace('range',10);
        fprintf('%s','unit');
        fillSpace('unit',10);
        fprintf('%s \n\n','description');
        inputs = config.config.IO_map.inputs;
        input_names = fieldnames(inputs);
        for m = 1:length(input_names)
            fprintf('%s',input_names{m});
            fillSpace(input_names{m},16);
            fprintf('%s',inputs.(input_names{m}).type.Text);
            fillSpace(inputs.(input_names{m}).type.Text,5);
            if(strcmp(inputs.(input_names{m}).type.Text,'DI')||strcmp(inputs.(input_names{m}).type.Text,'DO'))
                fprintf('[0,1]');
                fillSpace('[0,1]',10);
                fprintf('binary');
                fillSpace('binary',10);
            else
                fprintf('%s-%s',inputs.(input_names{m}).min.Text,inputs.(input_names{m}).max.Text);
                fillSpace([inputs.(input_names{m}).min.Text '-' inputs.(input_names{m}).max.Text],10);
                fprintf('%s',inputs.(input_names{m}).unit.Text);
                fillSpace(inputs.(input_names{m}).unit.Text,10);
            end
            fprintf('%s \n',inputs.(input_names{m}).description.Text);
        end
        fprintf('\n');
        fprintf('-----------------------------------------------\n');
        fprintf('Outputs (measured signals):\n');
        fprintf('%s','name');
        fillSpace('name',16);
        fprintf('%s','type');
        fillSpace('type',5);
        fprintf('%s','range');
        fillSpace('range',10);
        fprintf('%s','unit');
        fillSpace('unit',10);
        fprintf('%s \n\n','description');
        outputs = config.config.IO_map.outputs;
        output_names = fieldnames(outputs);
        for m = 1:length(output_names)
            fprintf('%s',output_names{m});
            fillSpace(output_names{m},16);
            fprintf('%s',outputs.(output_names{m}).type.Text);
            fillSpace(outputs.(output_names{m}).type.Text,5);
            if(strcmp(outputs.(output_names{m}).type.Text,'DI')||strcmp(outputs.(output_names{m}).type.Text,'DO'))
                fprintf('[0,1]');
                fillSpace('[0,1]',10);
                fprintf('binary');
                fillSpace('binary',10);
            else
                fprintf('%s-%s',outputs.(output_names{m}).min.Text,outputs.(output_names{m}).max.Text);
                fillSpace([outputs.(output_names{m}).min.Text '-' outputs.(output_names{m}).max.Text],10);
                fprintf('%s',outputs.(output_names{m}).unit.Text);
                fillSpace(outputs.(output_names{m}).unit.Text,10);
            end
            fprintf('%s \n',outputs.(output_names{m}).description.Text);
        end
        fprintf('\n');
    end

    function add2path(subdir,perm)
        current_dir = fileparts(which(mfilename));
        addpath(genpath([current_dir filesep subdir]));
        if(perm)
            savepath;
        end
    end

    function printCommandLink(link_text, commands)
        fprintf('<a href="matlab:%s">%s</a>',commands,link_text);
    end

    function out = getCommandLink(link_text, commands)
        out = sprintf('<a href="matlab:%s">%s</a>',commands,link_text);
    end

    function fillSpace(str,len)
        str_len = length(str);
        for x = 1:(len-str_len)
            fprintf(' ');
        end
    end

    function [contents,i] = loadContents(repofile)
        contents = {};
        fid = fopen(repofile);
        line = fgetl(fid);
        contents{1} = line;
        i = 1;
        while ischar(line)
            line = fgetl(fid);
            if length(line)>1
                i=i+1;
                contents{i} = line;
            end
        end
        fclose(fid);
    end

    function list = getRepoContents(repoUrl)
        current_dir = fileparts(which(mfilename));
        tempfile = [current_dir filesep 'tempf.xml'];
        repoUrl = strrep(repoUrl,'\','/');
        urlwrite([repoUrl 'contents.xml'],tempfile);
        list = xml2struct(tempfile);
        delete(tempfile);
    end

end