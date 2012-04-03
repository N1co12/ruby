require "net/ftp"
require "test/unit"
require "ostruct"
require "stringio"

class FTPTest < Test::Unit::TestCase
  SERVER_ADDR = "127.0.0.1"

  def test_not_connected
    ftp = Net::FTP.new
    assert_raise(Net::FTPConnectionError) do
      ftp.quit
    end
  end

  def test_parse227
    ftp = Net::FTP.new
    host, port = ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1,12,34)")
    assert_equal("192.168.0.1", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse227, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 ) foo bar (")
    end
  end

  def test_parse228
    ftp = Net::FTP.new
    host, port = ftp.send(:parse228, "228 Entering Long Passive Mode (4,4,192,168,0,1,2,12,34)")
    assert_equal("192.168.0.1", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse228, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,4,192,168,0,1,2,12,34)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (4,4,192,168,0,1,3,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (4,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,3,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 ) foo bar (")
    end
  end

  def test_parse229
    ftp = Net::FTP.new
    sock = OpenStruct.new
    sock.peeraddr = [nil, nil, nil, "1080:0000:0000:0000:0008:0800:200c:417a"]
    ftp.instance_variable_set(:@sock, sock)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (|||3106|)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (!!!3106!)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (~~~3106~)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse229, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (|!!3106!)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (   3106 )")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (\x7f\x7f\x7f3106\x7f)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 ) foo bar (")
    end
  end

  def test_parse_pasv_port
    ftp = Net::FTP.new
    assert_equal(12, ftp.send(:parse_pasv_port, "12"))
    assert_equal(3106, ftp.send(:parse_pasv_port, "12,34"))
    assert_equal(795192, ftp.send(:parse_pasv_port, "12,34,56"))
    assert_equal(203569230, ftp.send(:parse_pasv_port, "12,34,56,78"))
  end

  def test_login
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  # TODO: How can we test open_timeout?  sleep before accept cannot delay
  # connections.
  def _test_open_timeout_exceeded
    commands = []
    server = create_ftp_server(0.2) { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.open_timeout = 0.1
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Net::OpenTimeout) do
          ftp.login
        end
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_read_timeout_exceeded
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sleep(0.3)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Timeout::Error) do
          ftp.login
        end
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_read_timeout_not_exceeded
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_list_read_timeout_exceeded
    commands = []
    list_lines = [
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 foo.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 bar.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 baz.txt"
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      port_args = line.slice(/\APORT (.*)/, 1).split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      conn = TCPSocket.new(host, port)
      list_lines.each_with_index do |l, i|
        if i == 1
          sleep(0.5)
        else
          sleep(0.1)
        end
        conn.print(l, "\r\n")
      end
      conn.close
      sock.print("226 Directory send OK.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Timeout::Error) do
          ftp.list
        end
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\APORT /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_list_read_timeout_not_exceeded
    commands = []
    list_lines = [
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 foo.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 bar.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 baz.txt"
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      port_args = line.slice(/\APORT (.*)/, 1).split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      conn = TCPSocket.new(host, port)
      list_lines.each do |l|
        sleep(0.1)
        conn.print(l, "\r\n")
      end
      conn.close
      sock.print("226 Directory send OK.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(list_lines, ftp.list)
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\APORT /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_retrbinary_read_timeout_exceeded
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      port_args = line.slice(/\APORT (.*)/, 1).split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      binary_data.scan(/.{1,1024}/nm).each_with_index do |s, i|
        if i == 1
          sleep(0.5)
        else
          sleep(0.1)
        end
        conn.print(s)
      end
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ""
        assert_raise(Timeout::Error) do
          ftp.retrbinary("RETR foo", 1024) do |s|
            buf << s
          end
        end
        assert_equal(binary_data[0, 1024], buf)
        assert_match(/\APORT /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_retrbinary_read_timeout_not_exceeded
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      port_args = line.slice(/\APORT (.*)/, 1).split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      binary_data.scan(/.{1,1024}/nm) do |s|
        sleep(0.1)
        conn.print(s)
      end
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ""
        ftp.retrbinary("RETR foo", 1024) do |s|
          buf << s
        end
        assert_equal(binary_data, buf)
        assert_match(/\APORT /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_storbinary
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    stored_data = nil
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      port_args = line.slice(/\APORT (.*)/, 1).split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo\r\n")
      conn = TCPSocket.new(host, port)
      stored_data = conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.storbinary("STOR foo", StringIO.new(binary_data), 1024)
        assert_equal(binary_data, stored_data)
        assert_match(/\APORT /, commands.shift)
        assert_equal("STOR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_abort
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.recv(1024))
      sock.print("225 No transfer to ABOR.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        #ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.abort
        assert_equal("ABOR\r", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_status
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.recv(1024))
      sock.print("211 End of status\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.status
        assert_equal("STAT\r", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  private


  def create_ftp_server(sleep_time = nil)
    server = TCPServer.new(SERVER_ADDR, 0)
    Thread.start do
      begin
        if sleep_time
          sleep(sleep_time)
        end
        sock = server.accept
        begin
          yield(sock)
          sleep 0.1
        ensure
          sock.close
        end
      rescue
      end
    end
    def server.port
      addr[1]
    end
    return server
  end
end