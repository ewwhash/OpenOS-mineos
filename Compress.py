# Haven't written a single python program. first one, so don't judge 
import os

# Import Filesystem module if exists.

OCAFSignature = b'OCAF'
ignoredFiles = {
        b'.DS_Store': True
}
readBufferSize = 1024

def numberToByteArray(number):
    if number == 0:
      return bytearray(b'\x00')
    byte_array = bytearray()

    while number > 0:
        byte_array.append(number % 256)
        number //= 256

    return byte_array

def pack(archivePath, fileList):
    if isinstance(fileList, str):
        fileList = [fileList]

    with open(archivePath, 'wb') as handle:
        # Writing signature
        handle.write(OCAFSignature)
        # Writing encoding method (maybe will be used in future)
        handle.write(bytes([0]))

        # Recursive packing
        def doPack(fileList, localPath):
            for i in range(len(fileList)):
                filePath = fileList[i]
                filename = os.path.basename(filePath)

                currentLocalPath = os.path.join(localPath, filename)

                if filename not in ignoredFiles:
                    isDirectory = os.path.isdir(filePath)
                    # Writing byte of data type (0 is a file, 1 is a directory)
                    handle.write(bytes([int(isDirectory)]))
				            #  Writing string path as
                    #  <N bytes for reading a number that represents J bytes of path length>
					          # <J bytes for reading a number that represents path length>
					          # <PathLength bytes of path>
                    if not currentLocalPath.endswith("/") and isDirectory:
                      currentLocalPath += "/"
                    bytesForCountPathBytes = numberToByteArray(len(currentLocalPath))
                    pathLengthBytes = numberToByteArray(len(bytesForCountPathBytes))

                    handle.write(pathLengthBytes)
                    handle.write(bytesForCountPathBytes)
                    handle.write(currentLocalPath.encode())

                    if isDirectory:
                        # Obtaining new file list
                        newList = sorted(os.listdir(filePath))
                        # Creating absolute paths for list elements
                        newList = [os.path.join(filePath, name) for name in newList]

                        # Do recursion
                        success, reason = doPack(newList, currentLocalPath)
                        if not success:
                            return success, reason
                    else:
                        otherHandle = open(filePath, 'rb')
                        if otherHandle:
                            # Writing file size
                            fileSize = os.path.getsize(filePath)
                            fileSizeBytes = numberToByteArray(fileSize)[::-1]
                            fileSizeBytesLength = bytes([len(fileSizeBytes)])
                            handle.write(fileSizeBytesLength)
                            handle.write(fileSizeBytes)

                            # Writing file contents
                            while True:
                                data = otherHandle.read(readBufferSize)
                                
                                if data:
                                    handle.write(data)
                                else:
                                    break
                                
                            otherHandle.close()
                        else:
                            return False, "Failed to open file for reading: " + filePath

            return True, None
        
        success, reason = doPack(fileList, os.path.basename(os.path.abspath(fileList[0])))
        if not success:
            return False, "Pack failed: " + reason

        return True, None

pack("Rootfs.pkg", "./rootfs/")