#!/usr/bin/python

# Generate a prover worksheet for the c25519 circuit. Takes a parameter
# specifying the number of key bits per column: This should be a
# small number (<10), otherwise the circuit will be very tall and narrow.

# ./genpwscurve.py 255 will generate the circuit as a single column


import sys


def main(): 

    if (len(sys.argv) != 2):
        print "usage:", sys.argv[0], "<curve blocks per column>"
        return

    blocksPerColumn = int(sys.argv[1])
    numCols = 255 / blocksPerColumn
    columnSizes = [blocksPerColumn for _ in xrange(numCols)]
    extraBlocks = 255 - numCols * blocksPerColumn
    columnSizes.append(extraBlocks)

    inputOffset = 0
    blockOffset = 0
    outputOffset = 0
    bitCt = 0

    print inputLines
    for column in columnSizes:
        for i in xrange(column):
            print block(outputOffset, bitCt)
            bitCt += 1
            outputOffset += 26

        if (bitCt == 255):
            print outputLines(outputOffset)
        else:
            print ioLines(outputOffset)
            outputOffset += 4


def block(offset, bitCt):
    V = [i + offset for i in xrange(30)]
    repLines = """
MUX V{4} = V{0} mux V{2} bit {b0}
MUX V{5} = V{1} mux V{3} bit {b0}
MUX V{6} = V{2} mux V{0} bit {b0}
MUX V{7} = V{3} mux V{1} bit {b0}

P V{8} = V{4} + V{5} E
P V{9} = V{4} minus V{5} E
P V{10} = V{6} + V{7} E
P V{11} = V{6} minus V{7} E

P V{12} = V{8} * V{8} E
P V{13} = V{9} * V{9} E
P V{14} = V{9} * V{10} E
P V{15} = V{8} * V{11} E

P V{16} = V{12} * V{13} E
P V{17} = V{12} minus V{13} E
P V{18} = V{14} + V{15} E
P V{19} = V{14} minus V{15} E

P V{20} = V{17} * 121665 E
P V{21} = V{18} * V{18} E
P V{22} = V{19} * V{19} E

P V{23} = V{12} + V{20} E
P V{24} = V{22} * V0 E

P V{25} = V{17} * V{23} E

MUX V{26} = V{16} mux V{21} bit {b0}
MUX V{27} = V{25} mux V{24} bit {b0}
MUX V{28} = V{21} mux V{16} bit {b0}
MUX V{29} = V{24} mux V{25} bit {b0}

""".format(V[0], V[1], V[2], V[3], V[4], V[5], V[6], V[7],         \
           V[8], V[9], V[10], V[11], V[12], V[13], V[14], V[15],   \
           V[16], V[17], V[18], V[19], V[20], V[21], V[22], V[23], \
           V[24], V[25], V[26], V[27], V[28], V[29], b0= bitCt)

    return repLines

def ioLines(offset):
    V = [i + offset for i in xrange(12)]
    inputLines = """
P V{0} = I{0} E
P V{1} = I{1} E
P V{2} = I{2} E
P V{3} = I{3} E
""".format(V[4], V[5], V[6], V[7])

    outputLines = """
P O{8} = V{0} minus V{4} E
P O{9} = V{1} minus V{5} E
P O{10} = V{2} minus V{6} E
P O{11} = V{3} minus V{7} E
""".format(V[0], V[1], V[2], V[3], V[4], V[5], V[6], V[7],         \
           V[8], V[9], V[10], V[11])

    return inputLines + outputLines




def outputLines(offset):
    V = [i + offset for i in xrange(8)]
    lines = """
P O{4} = V{0} E
P O{5} = V{1} E
P O{6} = V{2} E
P O{7} = V{3} E
""".format(V[0], V[1], V[2], V[3], V[4], V[5], V[6], V[7])

    return lines

inputLines = """
P V0 = I0 E //x-coord of Q, the actual input
P V1 = 1 E //z = 1
P V2 = 1 E //x' = 1
P V3 = 0 E //z' = 0
"""



if __name__ == "__main__":
    main()

