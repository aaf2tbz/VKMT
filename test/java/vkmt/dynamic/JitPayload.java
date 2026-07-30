package vkmt.dynamic;

public final class JitPayload {
    private JitPayload() {
    }

    public static int compute(int value) {
        int result = value ^ 0x13579bdf;
        for (int index = 0; index < 16; ++index)
            result = Integer.rotateLeft(result + index * 0x10203,
                                        (index & 7) + 1);
        return result;
    }
}
