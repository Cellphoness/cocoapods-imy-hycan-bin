
module Pod
  class Command
    class Bin < Command
      class Code < Bin
        self.summary = '通过将二进制对应源码放置在临时目录中，让二进制出现断点时可以跳到对应的源码，方便调试。'

        self.description = <<-DESC
          通过将二进制对应源码放置在临时目录中，让二进制出现断点时可以跳到对应的源码，方便调试。
          在不删除二进制的情况下为某个组件添加源码调试能力，多个组件名称用空格分隔
        DESC

        self.arguments = [
            CLAide::Argument.new('NAME', false)
        ]
        def self.options
          [
              ['--all-clean', '删除所有已经下载的源码'],
              ['--clean', '删除所有指定下载的源码'],
              ['--list', '展示所有一级下载的源码以及其大小'],
              ['--source', '源码路径，本地路径,会去自动链接本地源码']
          ]
        end

        def initialize(argv)
          @codeSource =  argv.option('source') || nil
          @names = argv.arguments! unless argv.arguments.empty?
          @list = argv.flag?('list', false )
          @all_clean = argv.flag?('all-clean', false )
          @clean = argv.flag?('clean', false )

          @config = Pod::Config.instance
          # puts @config.inspect
          super
        end


        def run

          podfile_lock = File.join(Pathname.pwd,"Podfile.lock")
          raise "podfile.lock,不存在，请先pod install/update" unless File.exist?(podfile_lock)
          @lockfile ||= Lockfile.from_file(Pathname.new(podfile_lock) )

          if @list
            list
          elsif @clean
            clean
          elsif @all_clean
            all_clean
          elsif @names
            add
          end

          if @list && @clean && @names
            raise "请选择您要执行的命令。"
          end
        end

        #==========================begin add ==============

        def add
          if @names == nil
            raise "请输入要调试组件名，多个组件名称用空格分隔"
          end

          @names.each do  |name|
            lib_file = get_lib_path(name)
            unless File.exist?(lib_file)
              raise "找不到 #{lib_file}"
            end
            UI.puts "binary: #{lib_file}"

            target_path =  @codeSource || download_source(name)

            link(lib_file,target_path,name)
          end
        end

        #下载源码到本地
        def download_source(name)
          target_path =  File.join(source_root, name)
          UI.puts "download source: #{target_path}"
          FileUtils.rm_rf(target_path)

          find_dependency = find_dependency(name)
          # puts 'find:'
          # puts find_dependency.inspect
                
          podspec = findCodeRepoPath(name)

          find_dependency.external_source = {
            :podspec => podspec
          }

          spec = fetch_external_source(find_dependency, @config.podfile,@config.lockfile, @config.sandbox, true)

          # puts "spec:", spec

          download_request = Pod::Downloader::Request.new(:name => name, :spec => spec)
          Downloader.download(download_request, Pathname.new(target_path), :can_cache => true)

          target_path
        end

        #找出依赖
        def find_dependency (name)
          find_dependency = nil
          @config.podfile.dependencies.each do |dependency|
            if dependency.root_name.downcase == name.downcase
              find_dependency = dependency
              break
            end
          end
          find_dependency
        end

        # 获取external_source 下的仓库
        # @return spec
        def fetch_external_source(dependency, podfile, lockfile, sandbox, use_lockfile_options)
          source = ExternalSources.from_dependency(dependency, podfile.defined_in_file, true)
          source.fetch(sandbox)
        end

        # 用xxd自己爬取真实打包时的码源位置
        def readFromStaticFramework (binaryPath, repoName)

          # if !File.exist?(binaryPath)
          #   raise 'binaryPath not exit!'
          # end

          res = searchByMatchNum(5, binaryPath, repoName)

          if !res
            res = searchByMatchNum(10, binaryPath, repoName)
          end

          if !res
            res = searchByMatchNum(20, binaryPath, repoName)
          end

          # retry 3
          if !res
            raise 'retry 3! Error in find source path'
          end

          return res
        end

        def searchByMatchNum(num, binaryPath, repoName)
          repo = repoName
          if repoName.length > 15
            repo = repoName[0, 3]
            repo = 'Pods/' + repo
          else 
            repo = '/' + repo + '/'
          end

          # puts "repo:", "#{repo}"

          result = `xxd #{binaryPath} | grep '#{repo}' -B #{num}`
          splitArray = result.split(/\n--\n/)

          firstHit = ''
          lines = []
          if binaryPath.include?('.xcframework')
            firstHit = splitArray[splitArray.length-1]
            lines = firstHit.split(/\n/)
          else
            firstHit = splitArray[0]
            lines = firstHit.split(/\n/)
          end

          newLines = []
          lines.each do |item| 
            newLines.push(item[51, item.length])
          end

          # puts "newLines:", "#{newLines}"

          resLine = newLines.join('')

          prefix = '/Users/'
          surfix = repo
          match = resLine[/#{prefix}(.*?)#{surfix}/, 1]

          if !match
            return nil
          end

          if repoName.length > 15
            resLine = prefix + match + "Pods/#{repoName}" # Pods
          else
            resLine = prefix + match + "/#{repoName}"    
          end


          # puts "ln source:", "#{resLine}"
          
          return resLine  
        end
        #==========================link begin ==============

        #链接，.a文件位置， 源码目录，工程名=IMYFoundation
        def link(lib_file,target_path,basename)
          dir = ''
          is_dsym = false
          if lib_file.include?('dSYMs') 
            is_dsym = true
            dir = (`dwarfdump "#{lib_file}" | grep "AT_comp_dir" | head -1 | cut -d \\" -f2 `)        
          else
            dir = readFromStaticFramework(lib_file, basename)
          end

          # sub_path = "#{basename}/bin-archive/#{basename}" #change
          # dir = dir.gsub(sub_path, "").chomp  #change #change

          # UI.puts "dir = #{dir}" #change

          unless File.exist?(dir)
            # UI.puts "不存在 = #{dir}"
            begin
              FileUtils.mkdir_p(dir)
            rescue SystemCallError
              #判断用户目录是否存在
              array = dir.split('/')
              if array.length > 3
                root_path = '/' + array[1] + '/' + array[2]
                unless File.exist?(root_path)
                  raise "由于权限不足，请手动创建#{root_path} 后重试 sudo mkdir #{root_path}" #change
                end
              end
            end
          end

          if is_dsym
            FileUtils.rm_rf(File.join(dir,basename))
            `ln -s #{target_path} #{dir}/#{basename}`
            puts "ln -s #{target_path} #{dir}/#{basename}"
          else
            FileUtils.rm_rf(dir)
            `ln -s #{target_path} #{dir}`
            puts "ln -s #{target_path} #{dir}"
          end

          check(lib_file,dir,basename)
        end

        def check(lib_file,dir,basename)
          # file = `dwarfdump "#{lib_file}" | grep -E "DW_AT_decl_file.*#{basename}.*\\.m|\\.c" | head -1 | cut -d \\" -f2`
          # puts 'dir:', dir          
          # puts 'basename', basename
          # puts 'lib_file', lib_file
          # if File.exist?(file)
          #   raise "#{file} 不存在 请检测代码源是否正确~"
          # end
          UI.puts "link successfully!"
          UI.puts "view linked source at path: #{dir}"
        end

        def get_lib_path(name)
          dir = Pathname.new(File.join(Pathname.pwd,"Pods",name))
          lib_name = "lib#{name}.a"
          lib_path = File.join(dir,lib_name)

          unless File.exist?(lib_path)
            if dir.children.first.to_s.include?('.DS_Store')
              lib_path = File.join(dir.children[1],lib_name)
            else
              lib_path = File.join(dir.children.first,lib_name)
            end 
          end            

          unless File.exist?(lib_path)
            temp = ''
            dir.children.each do |item|
              if item.basename.to_s.include?('.framework')
                temp = item
              end
            end
            realName = Pathname.new(temp).basename.to_s
            if realName.include?('.framework')
              realName = realName.gsub(/.framework/, '')
            end
            lib_path = File.join(dir, "#{realName}.framework",realName)
          end
          
          unless File.exist?(lib_path)
            temp = ''
            dir.children.each do |item|
              if item.basename.to_s.include?('.xcframework')
                temp = item
              end
            end
            realName = Pathname.new(temp).basename.to_s
            if realName.include?('.xcframework')
              realName = realName.gsub(/.xcframework/, '')
            end
            
            lib_path = File.join(dir,"#{realName}.xcframework","ios-arm64_i386_x86_64-simulator", "dSYMs", "#{realName}.framework.dSYMs")

            unless File.exist?(lib_path)
              lib_path = File.join(dir,"#{realName}.xcframework","ios-arm64_x86_64-simulator", "dSYMs", "#{realName}.framework.dSYMs")
            end

            unless File.exist?(lib_path)
              lib_path = File.join(dir,"#{realName}.xcframework","ios-x86_64-simulator", "dSYMs", "#{realName}.framework.dSYMs")
            end 

            unless File.exist?(lib_path)
              lib_path = File.join(dir,"#{realName}.xcframework","ios-arm64_i386_x86_64-simulator", "#{realName}.framework", realName)
            end

            unless File.exist?(lib_path)
              lib_path = File.join(dir,"#{realName}.xcframework","ios-arm64_x86_64-simulator", "#{realName}.framework", realName)
            end

            unless File.exist?(lib_path)
              lib_path = File.join(dir,"#{realName}.xcframework","ios-x86_64-simulator", "#{realName}.framework", realName)
            end

          end
          lib_path
        end

        def cocoapodsRepos() 
          result = `pod repo list` #Pod::Command::Repo::List.run({})
          groups = result.split(/\n\n/)
          
          repos = []
          index = 0
          groups[0, groups.length-1].each do |item| 
            temp = item.split(/\n/)
            if index == 0
              lines = temp[1, temp.length-1]
            else
              lines = temp
            end
            key = lines.first
            repo = {}
            lines[1, lines.length-1].each do |value|
              tub = value.split(': ')
              valkey = tub.first.gsub(/- /, '')
              repo[valkey] = tub.last.gsub(/ /, '')
            end
            map = {}
            map[key] = repo
            repos.push(map)
            index += 1
          end
          repos
        end

        def findCodeRepoPath(podName)
          pathbasename = Pathname.pwd.basename.to_s
          sepcpath = File.join(Pathname.pwd, "..", "#{pathbasename}-build-temp", "bin-spec")
          result = File.join(sepcpath, "#{podName}.podspec.json")
          unless File.exist?(result)
            result = File.join(sepcpath, "#{podName}.podspec")
          end

          if File.exist?(result)
            return result
          else

            version = findPodVersion(File.join(Pathname.pwd,"Podfile.lock"), podName)
            if version == nil            
              raise "cannot find the versoin of your pod '#{name}''"
            end

            pathYml = File.join(@config.home_dir, 'bin_dev.yml')
            json = YAML.load(File.open(pathYml))
            repoUrl = json['code_repo_url']
            repos = cocoapodsRepos()
            path = ''
            repos.each do |item|
              val = item.values.first
              if val['URL'] == repoUrl
                path = val['Path']
              end
            end
            puts 'path ==>', path
            if path == ''
              raise 'cannot find correct repo in your cocoapods repos, please run "pod bin init" first!'
            end
            result = File.join(path, podName, version, "#{podName}.podspec.json")
            unless File.exist?(result)
              result = File.join(path, podName, version, "#{podName}.podspec")
            end
            if File.exist?(result)
              return result
            else
              raise 'cannot find your podpsec file in code repod, please run "pod bin push XXX.podspec.json" first!'
            end
          end
        end

        def findPodVersion(podfilePath, podName)
          podlockMap = YAML.load(File.open(podfilePath))
          pods = podlockMap['PODS']
          pods.each do |pod|
            if pod.class.to_s == 'Hash'
              keyName = pod.keys.first
              repo = keyName.split(' ').first
              version = keyName.split(' ').last
              if repo == podName
                return version.gsub(/\(/, '').gsub(/\)/, '')        
              end
            else
              repo = pod.split(' ').first
              version = pod.split(' ').last
              if repo == podName
                return version.gsub(/\(/, '').gsub(/\)/, '')        
              end
            end
          end
          return nil
         end

        #源码地址
        # def get_gitlib_iOS_path(name)
        #   "git@gitlab.xxx.com:iOS/#{name}.git"
        # end
        #要转换的地址，Github-iOS默认都是静态库
        # def git_gitlib_iOS_path
        #   'git@gitlab.xxx.com:Github-iOS/'
        # end


        #要转换的地址，Github-iOS默认都是静态库
        # def http_gitlib_GitHub_iOS_path
        #   'https://gitlab.xxx.com/Github-iOS/'
        # end

        #要转换的地址，iOS默认都是静态库
        # def http_gitlib_iOS_path
        #   'https://gitlab.xxx.com/iOS/'
        # end

        #==========================list begin ==============

        def list
          Dir.entries(source_root).each do |sub|
            UI.puts "- #{sub}" unless sub.include?('.')
          end
          UI.puts "加载完成"
        end


        #==========================clean begin ==============
        def all_clean
          FileUtils.rm_rf(source_root) if File.directory?(source_root)
          UI.puts "清理完成 #{source_root}"
        end

        def clean
          raise "请输入要删除的组件库" if @names.nil?
          @names.each do  |name|
            full_path = File.join(source_root,name)
            if File.directory?(full_path)
              FileUtils.rm_rf(full_path)
            else
              UI.puts "找不到 #{full_path}".yellow
            end
          end
          UI.puts "清理完成 #{@names.to_s}"
        end

        private

        def source_root
          dir = File.join(@config.cache_root,"Source")
          FileUtils.mkdir_p(dir) unless File.exist? dir
          dir
        end

      end
    end
  end
end
