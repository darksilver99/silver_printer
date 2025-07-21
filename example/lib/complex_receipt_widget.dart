import 'package:flutter/material.dart';

// Mock data classes for testing
class FoodItem {
  final String tmpSubject;
  final int quantity;
  final double tmpPrice;
  final String status;

  FoodItem({
    required this.tmpSubject,
    required this.quantity,
    required this.tmpPrice,
    this.status = '',
  });
}

class ComplexReceiptWidget extends StatelessWidget {
  final List<FoodItem> foodList;
  final String orderStatus;
  final String userName;
  final String? topImageUrl;
  final String? bottomImageUrl;
  final String? bottomText;

  const ComplexReceiptWidget({
    super.key,
    required this.foodList,
    required this.orderStatus,
    required this.userName,
    this.topImageUrl,
    this.bottomImageUrl,
    this.bottomText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // Use plain white instead of theme
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Image
            if (topImageUrl != null && topImageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(0.0),
                child: Image.network(
                  topImageUrl!,
                  width: 150.0,
                  fit: BoxFit.contain,
                ),
              ),

            // Restaurant Name
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Text(
                      userName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 32.0,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Order Title
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Text(
                      'Order.',
                      style: const TextStyle(
                        fontSize: 32.0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Food List
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: foodList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8.0),
                itemBuilder: (context, index) {
                  final item = foodList[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              '${item.tmpSubject} x ${item.quantity} ${item.status == 'ยกเลิก' ? 'ยกเลิก' : ''}',
                              style: const TextStyle(
                                fontSize: 24.0,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          item.tmpPrice.toString(),
                          style: const TextStyle(
                            fontSize: 24.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Total Price
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      _getTotalPrice().toStringAsFixed(2),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 32.0,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Date
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        DateTime.now().toString().split(' ')[0],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // QR Code Section
            if (bottomImageUrl != null && bottomImageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Divider(
                      thickness: 2.0,
                      indent: 32.0,
                      endIndent: 32.0,
                      color: Colors.grey[300],
                    ),
                    const Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Text(
                            'QR Code สำหรับชำระเงิน',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(0.0),
                      child: Image.network(
                        bottomImageUrl!,
                        width: 280.0,
                        height: 280.0,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Text
            if (bottomText != null && bottomText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          bottomText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _getTotalPrice() {
    if (orderStatus == 'เสร็จสิ้น' || orderStatus == 'ยกเลิก') {
      return foodList
          .where((item) => item.status != 'ยกเลิก')
          .fold(0.0, (sum, item) => sum + (item.tmpPrice * item.quantity));
    }
    return foodList.fold(
      0.0,
      (sum, item) => sum + (item.tmpPrice * item.quantity),
    );
  }
}
