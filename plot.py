import matplotlib.pyplot as plt
import numpy as np

arr_x = np.loadtxt("test_x.txt", delimiter=";")
arr_y = np.loadtxt("test_y.txt", delimiter=";")

plt.plot(arr_x[:,0],arr_x[:,1])
plt.plot(arr_y[:,0],arr_y[:,1])
plt.legend(["Audio","Envelope"])
plt.show()